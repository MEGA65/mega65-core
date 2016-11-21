`which echo` -n 'msg_version:     .byte "GIT COMMIT: ' >version.a65
`which echo` -n `git log | head -1 | cut -f2 -d" " | cut -c1-7,41-` >>version.a65
echo '",0' >>version.a65
