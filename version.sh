version=`git log | head | grep commit | head -1 | cut -f2 -d" "``[[ $(git diff --shortstat 2> /dev/null | tail -n1) != "" ]] && echo "+DIRTY"`
echo $version
cat version-template.vhdl | sed -e 's/GITCOMMIT/'${version}'/g' > version.vhdl
