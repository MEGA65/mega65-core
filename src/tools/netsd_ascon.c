/*
 * Ascon-AEAD128 (NIST SP 800-232) for netsd.py (MEGA65/mega65-core#965).
 *
 * A small, plain C version, built into a shared object by netsd_crypto.py
 * on first use and called through ctypes.  The pure-Python version in
 * netsd_crypto.py is the fallback; test_netsd.py checks both against
 * pyascon, the designers' reference.
 *
 *   cc -O2 -shared -fPIC -o netsd_ascon.so netsd_ascon.c
 */
#include <stddef.h>
#include <stdint.h>
#include <string.h>

typedef uint64_t u64;

static u64 load(const uint8_t *p, size_t n)
{
  u64 x = 0;
  for (size_t i = 0; i < n; i++)
    x |= (u64)p[i] << (8 * i);
  return x;
}

static void store(uint8_t *p, u64 x, size_t n)
{
  for (size_t i = 0; i < n; i++)
    p[i] = (uint8_t)(x >> (8 * i));
}

#define ROR(x, n) (((x) >> (n)) | ((x) << (64 - (n))))

static void permute(u64 *s, int rounds)
{
  for (int r = 12 - rounds; r < 12; r++) {
    u64 x0 = s[0], x1 = s[1], x2 = s[2], x3 = s[3], x4 = s[4], t0, t1, t2, t3, t4;
    x2 ^= (u64)(0xf0 - r * 0x0f);
    x0 ^= x4; x4 ^= x3; x2 ^= x1;
    t0 = ~x0 & x1; t1 = ~x1 & x2; t2 = ~x2 & x3; t3 = ~x3 & x4; t4 = ~x4 & x0;
    x0 ^= t1; x1 ^= t2; x2 ^= t3; x3 ^= t4; x4 ^= t0;
    x1 ^= x0; x0 ^= x4; x3 ^= x2; x2 = ~x2;
    s[0] = x0 ^ ROR(x0, 19) ^ ROR(x0, 28);
    s[1] = x1 ^ ROR(x1, 61) ^ ROR(x1, 39);
    s[2] = x2 ^ ROR(x2, 1) ^ ROR(x2, 6);
    s[3] = x3 ^ ROR(x3, 10) ^ ROR(x3, 17);
    s[4] = x4 ^ ROR(x4, 7) ^ ROR(x4, 41);
  }
}

/* IV: version 1, a = 12, b = 8, 128-bit tag, 16-byte rate */
static const uint8_t IV[8] = { 0x01, 0x00, 0x8c, 0x80, 0x00, 0x10, 0x00, 0x00 };

static void start(u64 *s, const uint8_t *key, const uint8_t *nonce, const uint8_t *ad, size_t adlen)
{
  u64 k0 = load(key, 8), k1 = load(key + 8, 8);
  s[0] = load(IV, 8);
  s[1] = k0;
  s[2] = k1;
  s[3] = load(nonce, 8);
  s[4] = load(nonce + 8, 8);
  permute(s, 12);
  s[3] ^= k0;
  s[4] ^= k1;
  if (adlen) {
    while (adlen >= 16) {
      s[0] ^= load(ad, 8);
      s[1] ^= load(ad + 8, 8);
      permute(s, 8);
      ad += 16;
      adlen -= 16;
    }
    uint8_t last[16] = { 0 };
    memcpy(last, ad, adlen);
    last[adlen] = 0x01;
    s[0] ^= load(last, 8);
    s[1] ^= load(last + 8, 8);
    permute(s, 8);
  }
  s[4] ^= (u64)1 << 63;
}

static void finish(u64 *s, const uint8_t *key, uint8_t *tag)
{
  u64 k0 = load(key, 8), k1 = load(key + 8, 8);
  s[2] ^= k0;
  s[3] ^= k1;
  permute(s, 12);
  store(tag, s[3] ^ k0, 8);
  store(tag + 8, s[4] ^ k1, 8);
}

/* ct must have room for ptlen + 16 bytes (ciphertext, then the tag) */
void netsd_ascon_encrypt(const uint8_t *key, const uint8_t *nonce, const uint8_t *ad, size_t adlen,
                         const uint8_t *pt, size_t ptlen, uint8_t *ct)
{
  u64 s[5];
  start(s, key, nonce, ad, adlen);
  while (ptlen >= 16) {
    s[0] ^= load(pt, 8);
    s[1] ^= load(pt + 8, 8);
    store(ct, s[0], 8);
    store(ct + 8, s[1], 8);
    permute(s, 8);
    pt += 16;
    ct += 16;
    ptlen -= 16;
  }
  uint8_t last[16] = { 0 };
  memcpy(last, pt, ptlen);
  last[ptlen] = 0x01;
  s[0] ^= load(last, 8);
  s[1] ^= load(last + 8, 8);
  store(last, s[0], 8);
  store(last + 8, s[1], 8);
  memcpy(ct, last, ptlen);
  finish(s, key, ct + ptlen);
}

/* ctlen includes the 16-byte tag.  Returns 0 and the plaintext in pt
   (ctlen - 16 bytes), or -1 with pt zeroed if the tag is wrong. */
int netsd_ascon_decrypt(const uint8_t *key, const uint8_t *nonce, const uint8_t *ad, size_t adlen,
                        const uint8_t *ct, size_t ctlen, uint8_t *pt)
{
  if (ctlen < 16)
    return -1;
  size_t len = ctlen - 16, n = len;
  const uint8_t *tag = ct + len;
  uint8_t *out = pt;
  u64 s[5];
  start(s, key, nonce, ad, adlen);
  while (n >= 16) {
    u64 c0 = load(ct, 8), c1 = load(ct + 8, 8);
    store(out, s[0] ^ c0, 8);
    store(out + 8, s[1] ^ c1, 8);
    s[0] = c0;
    s[1] = c1;
    permute(s, 8);
    ct += 16;
    out += 16;
    n -= 16;
  }
  uint8_t last[16], ks[16];
  store(ks, s[0], 8);
  store(ks + 8, s[1], 8);
  memcpy(last, ks, 16);
  for (size_t i = 0; i < n; i++) {
    out[i] = ks[i] ^ ct[i];
    last[i] = ct[i];
  }
  last[n] ^= 0x01;
  s[0] = load(last, 8);
  s[1] = load(last + 8, 8);
  uint8_t want[16];
  finish(s, key, want);
  uint8_t diff = 0;
  for (int i = 0; i < 16; i++)
    diff |= want[i] ^ tag[i];
  if (diff) {
    memset(pt, 0, len);
    return -1;
  }
  return 0;
}
