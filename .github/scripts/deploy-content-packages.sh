#!/bin/sh
# This script should deploy or build and deploy a given package
# $1 = $WORKSPACE
# $2 = Group:agency|partner
# $3 = ProjectName:output
# $4 = Environment:dev|stage|production
# $5 = Instance:author|publish|both
# $6 = Pool:kstl|kfr

help() {
        echo "invalid number of arguments or help requested"
        echo "parameters: workspace group-name project-name environment instance pool"
}

case $1 in
        --help | -h | -help | -hlep)
        help
        ;;
*)
esac

#Setup variables
if [ -z "$workspace" ]; then
        workspace=$1
fi

if [ -z "$group" ]; then
        group=$2
fi

if [ -z "$project" ]; then
        project=$3
fi

if [ -z "$environment" ]; then
        environment=$4
fi

if [ -z "$instance" ]; then
        instance=$5
fi

if [ -z "$pool" ]; then
        pool=$6
fi

function getpackages {
#Create Package Array
cd $workspace
X=0
for i in `ls *.zip` ; do
        package[$X]="$i"
        let "X= $X + 1 "
done

if [ $X -eq 0 ]; then
        echo "no packages found in path `pwd`!"
        exit 1
else
        #Run package installer
        for n in ${package[@]}; do
                echo "Sending $packagename to deploy script."
                packagename=`echo ${n} | awk -F'.zip' '{print $1}'`
                # /var/lib/build/scripts/deploy/deploy-package-filter.sh $workspace $packagename $group $project $environment $instance $pool
        done
fi
}

if [ `echo $@ | wc -w` -eq 6 ]; then
        getpackages
else
        help
fi
