version=`git log | head | grep commit | head -1 | cut -f2 -d" "``[[ $(git diff --shortstat 2> /dev/null | tail -n1) != "" ]] && echo "+DIRTY"`
echo $version
cat version-template.vhdl | sed -e 's/GITCOMMIT/'${version}'/g' > version.vhdl

version=`git log | head | grep commit | head -1 | cut -f2 -d" " | tr "abcdef" "ABCDEF" | cut -c1-15`\*`[[ $(git diff --shortstat 2> /dev/null | tail -n1) != "" ]] && echo "+DIRTY"`
echo $version
echo 'msg_gitcommit: .byte "GIT COMMIT: '${version}'",0' > version.a65
