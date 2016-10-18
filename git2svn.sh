#!/bin/bash
#
# derived from https://github.com/guilhermechapiewski/git2svn
#
# git2svn.sh \
#   -g https://github.com/user/myrepo.git \
#   -s https://hubzero.org/tools/myrepo/svn/trunk \
#   -c /www/hub/hubconfiguration.php


function svn_checkin {
    echo '... adding files'
    for file in `svn st ${svn_dir} | awk -F" " '{print $1 "|" $2}'`; do
        fstatus=`echo ${file} | cut -d"|" -f1`
        fname=`echo ${file} | cut -d"|" -f2`

        if [ "${fstatus}" == "?" ]; then
            if [[ "${fname}" == *@* ]]; then
                svn add $fname@;
            else
                svn add ${fname};
            fi
        fi
        if [ "${fstatus}" == "!" ]; then
            if [[ "${fname}" == *@* ]]; then
                svn rm $fname@;
            else
                svn rm ${fname};
            fi
        fi
        if [ "${fstatus}" == "~" ]; then
            rm -rf ${fname};
            svn up ${fname};
        fi
    done
    echo '... finished adding files'
}

function svn_commit {
    echo "... committing -> [${author}]: ${msg}";
    cd ${svn_dir} && svn ${svn_auth} commit -m "[${author}]: ${msg}" && cd ${base_dir};
    echo '... committed!'
}


git_repo_url=""
svn_repo_url=""
project_name=`mktemp -u XXXXXXXXXX`
hubconfig=""
options=":c:g:p:s:"

# parse the command line flags and options
# separate flags from options

let nNamedArgs=0
let nUnnamedArgs=0
while (( "$#" ))
do
   case $1 in
      -* )
           namedArgs[${nNamedArgs}]=$1
           let nNamedArgs++
           shift
           namedArgs[${nNamedArgs}]=$1
           let nNamedArgs++
           shift
           ;;
       * )
           unnamedArgs[${nUnnamedArgs}]=$1
           let nUnnamedArgs++
           shift
           ;;
   esac
done

while getopts "${options}" Option "${namedArgs[@]}"
do
   case ${Option} in
      c ) hubconfig=${OPTARG};;
      g ) git_repo_url=${OPTARG};;
      p ) project_name=${OPTARG};;
      s ) svn_repo_url=${OPTARG};;
   esac
done

# grab the svn username and password from the hub configuration file.
# these regexps work as long as the strings are single quoted.
svn_user=`grep svn_user ${hubconfig} | sed -n "s/^.*'\(.*\)'.*;/\1/p"`;
svn_pass=`grep svn_password ${hubconfig} | sed -n "s/^.*'\(.*\)'.*;/\1/p"`;
svn_auth="--username ${svn_user} --password ${svn_pass}";

base_dir=`pwd`;
repos_dir=`mktemp -d -p . contribtool.XXXXXXXXXX`;
git_dir="${repos_dir}/${project_name}.github";
svn_dir="${repos_dir}/${project_name}.hubzero";


# clone the git repository
git clone -q ${git_repo_url} ${git_dir};

# check out the svn repository
svn checkout -q ${svn_repo_url} ${svn_dir};

# find the latest commit in the git repo
commit=`cd ${git_dir} && git rev-list --all -n 1 && cd ${base_dir}`;

echo "Committing ${commit}...";
author=`cd ${git_dir} && git log -n 1 --pretty=format:%an ${commit} && cd ${base_dir}`;
msg=`cd ${git_dir} && git log -n 1 --pretty=format:%s ${commit} && cd ${base_dir}`;

# Checkout the current commit on git
echo '... checking out commit on Git'
cd ${git_dir} && git checkout -q ${commit} && cd ${base_dir};

# Delete everything from SVN and copy new files from Git
# Keep the bare minimum directory structure for hubzero applications
echo '... copying files'
rm -rf ${svn_dir}/*;
cp -prf ${git_dir}/* ${svn_dir}/;
mkdir -p ${svn_dir}/bin ${svn_dir}/data ${svn_dir}/doc \
         ${svn_dir}/examples ${svn_dir}/middleware \
         ${svn_dir}/rappture ${svn_dir}/src;


# Remove Git specific files from SVN
for ignorefile in `find ${svn_dir} | grep .git | grep .gitignore`;
do
    rm -rf ${ignorefile};
done

# Add new files to SVN and commit
svn_checkin
svn_commit;

# cleanup temp directories
rm -rf ${repos_dir}
