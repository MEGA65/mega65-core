/*
  RLE compress a tileset representation of an image.

  Bit 7 of each code byte indicates if raw bytes (0) or an RLE sequence (1)
  follows.  The lower bits are the count of bytes.  If raw, then the bytes
  follow. If RLE, then the single byte value follows.

  Since tilesets have repeating 00 ff motifs, we also allow for repeating
  double char seqences, by using code byte 0x80 which will never otherwise
  get used, followed by 2 bytes of repeat.  This also allows us to encode
  upto 512 bytes using only 4 bytes, instead of needing 10 bytes if we
  use the normal 0 - 127 count RLE.

  Dynamic programming is used to select optimal (i.e., shortest) encoding,
  so it will automatically pick which combination of tokens is best.
*/

#define MAX_RAW_SIZE (128 * 1024)

#include <stdio.h>
#include <stdlib.h>
#include <strings.h>

unsigned char raw[MAX_RAW_SIZE];
int raw_size;

typedef struct dp_item {
  unsigned char code_byte;
  unsigned char code_byte2;
  unsigned char *raw_region;
  int cumulative_cost;
  int parent;
  int offset;
} dp_item;

dp_item dp_list[MAX_RAW_SIZE + 1];

int main(int argc, char **argv)
{
  if (argc != 3) {
    fprintf(stderr, "usage: packtilesest <input tileset> <output compressed file>\n");
    exit(-3);
  }

  int retVal = 0;
  do {

    FILE *f = fopen(argv[1], "r");
    if (!f) {
      retVal = -1;
      fprintf(stderr, "Could not open file '%s'\n", argv[1]);
      break;
    }

    raw_size = fread(raw, 1, MAX_RAW_SIZE, f);
    if (raw_size < 1) {
      retVal = -1;
      fprintf(stderr, "Couldd not read contents of input file.\n");
      break;
    }
    fclose(f);

    printf("Compressing file of %d bytes.\n", raw_size);

    // Initialise DP list as infinite cost
    for (int i = 0; i <= MAX_RAW_SIZE; i++) {
      dp_list[i].offset = i;
      dp_list[i].code_byte = 0x00;            // invalid code byte
      dp_list[i].cumulative_cost = 999999999; // infinite cost
      dp_list[i].parent = -1;                 // Links to invalid parent
    }

    // To get to the start of the file has no cost
    dp_list[0].cumulative_cost = 0;

    // Now iterate through the file
    for (int start = 0; start < raw_size; start++) {
      int cumulative_cost = dp_list[start].cumulative_cost;

      // Consider cost of encoding with non-RLE
      for (int end = start + 1; end <= raw_size && (end - start) < 128; end++) {
        int this_cost = 1 + (end - start);
        if (this_cost + cumulative_cost < dp_list[end].cumulative_cost) {
          // This is a superior option to what is currently recorded.
          dp_list[end].code_byte = 0x00 + (end - start);
          dp_list[end].cumulative_cost = this_cost + cumulative_cost;
          dp_list[end].raw_region = &raw[start];
          dp_list[end].parent = start;
        }
      }

      // Now try RLE
      for (int end = start + 1; raw[end - 1] == raw[start] && end <= raw_size && (end - start) < 128; end++) {
        int this_cost = 1 + 1;
        if (this_cost + cumulative_cost < dp_list[end].cumulative_cost) {
          // This is a superior option to what is currently recorded.
          dp_list[end].code_byte = 0x80 + (end - start);
          dp_list[end].cumulative_cost = this_cost + cumulative_cost;
          dp_list[end].raw_region = &raw[start];
          dp_list[end].parent = start;
        }
      }

      // Now try RLE of pairs of bytes
      for (int end = start + 2;
           (raw[end - 2] == raw[start]) && (raw[end - 1] == raw[start + 1]) && end <= raw_size && (end - start) < 512;
           end += 2) {
        int this_cost = 1 + 1 + 2;
        if (this_cost + cumulative_cost < dp_list[end].cumulative_cost) {
          // This is a superior option to what is currently recorded.
          dp_list[end].code_byte = 0x80;
          dp_list[end].code_byte2 = (end - start) >> 1;
          dp_list[end].cumulative_cost = this_cost + cumulative_cost;
          dp_list[end].raw_region = &raw[start];
          dp_list[end].parent = start;
        }
      }
    }

    // Report on compressed size
    printf("Compressed size is %d bytes\n", dp_list[raw_size].cumulative_cost);

    dp_item *queue[MAX_RAW_SIZE + 1];
    int queue_len = 0;
    int offset = raw_size;
    while (offset > 0) {
      queue[queue_len] = &dp_list[offset];
      queue_len++;
      if (dp_list[offset].parent >= offset) {
        fprintf(stderr, "ERROR: Circular dynamic programming path detected.\n");
        exit(-3);
      }
      offset = dp_list[offset].parent;
    }

    printf("File encoded using %d tokens\n", queue_len);

    FILE *o = fopen(argv[2], "w");
    if (!o) {
      retVal = -1;
      fprintf(stderr, "ERROR: Could not open output file '%s'\n", argv[2]);
      break;
    }
    // Write out contents of queue in reverse order
    for (int i = queue_len - 1; i >= 0; i--) {
      fputc(queue[i]->code_byte, o);
      if (queue[i]->code_byte == 0x80) {
        fputc(queue[i]->code_byte2, o);
        fputc(queue[i]->raw_region[0], o);
        fputc(queue[i]->raw_region[1], o);
      }
      else if (queue[i]->code_byte & 0x80)
        fputc(*queue[i]->raw_region, o);
      else
        fwrite(queue[i]->raw_region, queue[i]->code_byte & 0x7f, 1, o);
    }
    // Terminate with $00 char to mark end of packed data
    fputc(0x00, o);
    fclose(o);

    // Now verify
    o = fopen(argv[2], "r");
    if (!o) {
      retVal = -1;
      fprintf(stderr, "ERROR: Could not open output file '%s' for verification\n", argv[2]);
      break;
    }
    unsigned char packed[MAX_RAW_SIZE * 2];
    int packed_len = fread(packed, 1, MAX_RAW_SIZE * 2, o);
    printf("Read %d packed bytes for verification.\n", packed_len);

    unsigned char unpacked[MAX_RAW_SIZE];
    int unpacked_len = 0;
    offset = 0;
    while (offset <= packed_len && unpacked_len < raw_size) {
      int count = packed[offset] & 0x7f;
      if (packed[offset] == 0x80) {
        count = packed[offset + 1];
        for (int i = 0; i < count; i++) {
          unpacked[unpacked_len++] = packed[offset + 2];
          unpacked[unpacked_len++] = packed[offset + 3];
        }
        offset += 4;
      }
      else if (packed[offset] & 0x80) {
        // Decode RLE
        for (int i = 0; i < count; i++)
          unpacked[unpacked_len++] = packed[offset + 1];
        offset += 2;
      }
      else {
        bcopy(&packed[offset + 1], &unpacked[unpacked_len], count);
        offset += 1 + count;
        unpacked_len += count;
      }
    }
    // Skip end $00 marker
    if (!packed[offset])
      offset++;

    if (unpacked_len != raw_size) {
      fprintf(stderr, "ERROR: Unpacked len = %d during verification. Should have been %d\n", unpacked_len, raw_size);
      retVal = 1;
      o = fopen("verify.out", "w");
      if (o) {
        fwrite(unpacked, unpacked_len, 1, o);
        fclose(o);
      }

      break;
    }

    if (offset != packed_len) {
      fprintf(stderr, "ERROR: Only used %d of %d bytes during unpacking.\n", offset, packed_len);
      o = fopen("verify.out", "w");
      if (o) {
        fwrite(unpacked, unpacked_len, 1, o);
        fclose(o);
      }
      retVal = 1;
      break;
    }

    for (int i = 0; i < raw_size; i++) {
      if (raw[i] != unpacked[i]) {
        fprintf(stderr, "ERROR: Verification error at offset %d : saw 0x%02x instead of 0x%02x\n", i, unpacked[i], raw[i]);
        retVal = 1;

        o = fopen("verify.out", "w");
        if (o) {
          fwrite(unpacked, unpacked_len, 1, o);
          fclose(o);
        }

        break;
      }
    }

  } while (0);

  return retVal;
}
