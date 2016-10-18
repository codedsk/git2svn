#!/bin/bash
#
# derived from https://github.com/guilhermechapiewski/git2svn
#
# git2svn.sh \
#   -g https://github.com/user/myrepo.git \
#   -s https://hubzero.org/tools/myrepo/svn/trunk \
#   -c /www/hub
#
# if no svn directory is provided, but a project name is,
# then use hubconfiguration.php to guess at the svn repository name
# git2svn.sh \
#   -g https://github.com/user/myrepo.git \
#   -p myrepo
#   -c /www/hub

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
hubconfig="."
t_repos_base="."
options=":c:g:p:r:s:"

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
      r ) t_repos_base=${OPTARG};;
      s ) svn_repo_url=${OPTARG};;
   esac
done


# exit immediately on error
set -e

# input validation

# regexp only works with ascii urls
url_regex='^https?://[-A-Za-z0-9\+&@#/%?=~_|!:,.;]*[-A-Za-z0-9\+&@#/%=~_|]$';
proj_regex='^[-A-Za-z0-9\+@#/%?=~_|!:,.]+$';

if [[ ! -d ${t_repos_base} ]] ; then
    echo "ERROR: Temporary repository directory \"${t_repos_base}\" does not exist.";
    exit 3;
fi

if [[ ! -r ${hubconfig}/hubconfiguration.php ]] ; then
    echo "ERROR: Hub configuration file \"${hubconfig}/hubconfiguration.php\" is not readable";
    exit 4;
else
    hubconfig="${hubconfig}/hubconfiguration.php"
fi

if [[ ! ${project_name} =~ ${proj_regex} ]] ; then
    echo "ERROR: Project name contains invalid characters: ${project_name}";
    exit 5;
fi

if [[ ! ${git_repo_url} =~ ${url_regex} ]] ; then
    echo "ERROR: Git repository does not look like a url: ${git_repo_url}";
    exit 1;
fi

if [[ ! ${svn_repo_url} =~ ${url_regex} ]] ; then
    if [[ ! ${svn_repo_url} =~ ${proj_regex} ]] ; then
        echo "ERROR: Subversion repository does not look like a url: ${svn_repo_url}";
        exit 2;
    else
        # looks like the svn_repo_url is a project name
        # try to guess the repository name from forgeURL

        forgeURL=`grep forgeURL ${hubconfig} | sed -n "s/^.*'\(.*\)'.*;/\1/p"`;
        svn_repo_url="${forgeURL}/tools/${svn_repo_url}/svn/trunk"
    fi
fi

# grab the svn username and password from the hub configuration file.
# these regexps work as long as the strings are single quoted.
svn_user=`grep svn_user ${hubconfig} | sed -n "s/^.*'\(.*\)'.*;/\1/p"`;
svn_pass=`grep svn_password ${hubconfig} | sed -n "s/^.*'\(.*\)'.*;/\1/p"`;
svn_auth="--username ${svn_user} --password ${svn_pass}";

base_dir=`pwd`;
repos_dir=`mktemp -d -p ${t_repos_base} contribtool.XXXXXXXXXX`;
git_dir="${repos_dir}/${project_name}.github";
svn_dir="${repos_dir}/${project_name}.hubzero";

# clone the git repository
git clone -q "${git_repo_url}" ${git_dir};

# check out the svn repository
svn checkout -q "${svn_repo_url}" ${svn_dir};

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
svn_checkin;
svn_commit;

# cleanup temp directories
rm -rf ${repos_dir};

exit 0;
