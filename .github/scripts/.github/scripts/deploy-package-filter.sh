#!/bin/sh
# This script should deploy or build and deploy a given package
# $1 = PackagePath:$WORKSPACE/ui/target/
# $2 = PackageName:output-ui-1-0
# $3 = Group:agency|partner
# $4 = ProjectName:output
# $5 = Environment:dev|stage|production
# $6 = Instance:author|publish|both
# $7 = Pool:kstl|kfr
# $8 = DebugFlag:debug


echo "able to connect and trigger the .sh script"
# help() {
        # echo "invalid number of arguments or help requested"
        # echo "parameters: target-jar-location package-name group-name project-name environment instance pool"
# }

# function validateFilter(){
        # result=$(java -cp /var/lib/build/scripts/deploy/CheckFilter com.CheckFilter $1 $2 $3)
        # echo "$result"
# }

# function get_fn_results(){
        # command=$1
        # len=${#result}-2
        # result=${result:1:len}
        # IFS=',' read -ra RES <<< "$result"

        # success=${RES[0]}
        # message=${RES[1]}
        # #path=${message#*/}
        # #path=${path:0:${#path}-1}

        # if [[ $success == *true* ]]; then
                # echo ""
                # echo "Successfully processed $command command."
                # echo ""
        # else
                # echo ""
                # echo "Funtion $command failed with error: $message"
                # echo ""
                # exit 1
        # fi
# }
# function find_package_name(){
        # for i in $propfile; do
                # echo $i
                # if [[ $i == *name* ]]; then
                        # propname=`echo $i | cut -f2 -d">"|cut -f1 -d"<"`
                # fi
        # done
# }

# function list_packages(){
        # packagevar=$1
        # packagetst=$2
        # echo ""
        # echo "Getting the list of packages on server $AEM_DEPLOY_IP:$AEM_DEPLOY_PORT..."
        # echo "Looking for package $packagevar"
        # echo ""
        # N=0
        # packfnd=0
        # blnF=0
        # /usr/bin/curl -u $AEM_DEPLOY_USERNAME:$AEM_DEPLOY_PASSWORD http://$AEM_DEPLOY_IP:$AEM_DEPLOY_PORT/crx/packmgr/service.jsp?cmd=ls > $packagetst
        # while read i; do
                # if [[ $blnF = "true" ]]; then
                        # version=`echo $i | cut -f2 -d">"|cut -f1 -d"<"`
                        # break
                # fi
                # if [[ $i =~ "<name>" ]]; then
                        # packagename=`echo $i | cut -f2 -d">"|cut -f1 -d"<"`
                        # if [[ $packagename == $1 ]]; then
                                # if $bZip ; then
                                        # group=${pcklist[$N-1]}
                                        # group=${group:7:${#group}-15}
                                        # path="/etc/packages/$group/"
                                        # echo ""
                                        # echo "Found installed package path $path"
                                        # echo ""
                                        # packfnd=1
                                        # blnF="true"
                                # else
                                        # group=${pcklist[$N-1]}
                                        # group=${group:7:${#group}-15}
                                        # path="/etc/packages/$group/"
                                        # echo ""
                                        # echo "Found installed package $path$packagevar"
                                        # echo ""
                                        # packfnd=1
                                        # blnF="true"
                                # fi
                        # fi
                # fi
                # pcklist[$N]="$i"
                # let "N= $N + 1"
        # done<$packagetst
        # if [[ $packfnd != 1 ]]; then
                # echo ""
                # echo "Package not found $packagevar!"
                # echo ""
        # fi
# }

# function main {
        # #get configuration from properties file
        # if $bDebug ; then
                # if [ -f ../../config/server.properties ]; then
                        # FILE=../../config/server.properties
                        # source $FILE
                # else
                        # echo "Configuration file not found!"
                        # exit 1
                # fi
        # else
                # if [ -f /var/lib/build/config/server.properties ]; then
                        # FILE=/var/lib/build/config/server.properties
                        # source $FILE
                # else
                        # echo "Configuration file not found!"
                        # exit 1
                # fi
        # fi

        # #setup package variables
        # echo "Looking for $package"
        # jarfileloc=$inputpath$(ls -t $inputpath |grep "^"$package)

        # echo "Package path: $jarfileloc"

        # #check file size limitation
        # filesize=$jarfileloc
        # maximumsize=$max_package_size
        # actualsize=$(du -b -m "$filesize" | cut -f 1)
        # if [[ $actualsize -lt $maximumsize ]]; then
                # echo "File size is ${actualsize}MB"
                # echo "Size is under $maximumsize megabytes and is permitted to run"
        # else
                # echo "File size is ${actualsize}MB"
                # echo "Size is over $maximumsize megabytes and is not permitted to run!"
                # echo "Please reduce the overall size or split into smaller packages."
                # exit 1
        # fi

        # #check if input file is a zip or jar file
        # if echo $jarfileloc | grep -q "\.zip"; then
                # echo "Zip file detected."
                # bZip="true"
        # elif echo $jarfileloc | grep -q "\.jar"; then
                # echo "Jar file detected."
                # bZip="false"
        # else
                # echo "File type not supported: $jarfileloc"
                # exit 1
        # fi

        # #setup server configuration values
        # servereval="$environment:$instance:$pool"
        # echo $servereval
        # case "$servereval" in
                # dev:author:dam)
                # AEM_SERVERS=$dev_dam_aem_authors
                # buildAllowed="development:$dev_build_allowed"
                # ;;

                # dev:publish:dam)
                # AEM_SERVERS=$dev_dam_aem_publishers
                # buildAllowed="development:$dev_build_allowed"
                # ;;

                # dev:both:dam)
                # AEM_SERVERS="$dev_dam_aem_authors,$dev_dam_aem_publishers"
                # buildAllowed="development:$dev_build_allowed"
                # ;;

                # devqa:author:dam)
                # AEM_SERVERS=$devqa_dam_aem_authors
                # buildAllowed="development:$dev_build_allowed"
                # ;;

                # devqa:publish:dam)
                # AEM_SERVERS=$devqa_dam_aem_publishers
                # buildAllowed="development:$dev_build_allowed"
                # ;;

                # devqa:both:dam)
                # AEM_SERVERS="$devqa_dam_aem_authors,$devqa_dam_aem_publishers"
                # buildAllowed="development:$dev_build_allowed"
                # ;;

                # stage:author:dam)
                # AEM_SERVERS=$stg_dam_aem_authors
                # buildAllowed="stage:$stage_build_allowed"
                # ;;

                # stage:publish:dam)
                # AEM_SERVERS=$stg_dam_aem_publishers
                # buildAllowed="stage:$stage_build_allowed"
                # ;;

                # stage:both:dam)
                # AEM_SERVERS="$stg_dam_aem_authors,$stg_dam_aem_publishers"
                # buildAllowed="stage:$stage_build_allowed"
                # ;;

                # preview:publish:dam)
                # AEM_SERVERS=$prv_dam_aem_publishers
                # buildAllowed="production:$production_build_allowed"
                # ;;

                # production:author:dam)
                # AEM_SERVERS=$prd_dam_aem_authors
                # buildAllowed="production:$production_build_allowed"
                # ;;

                # production:publish:dam)
                # AEM_SERVERS=$prd_dam_aem_publishers
                # buildAllowed="production:$production_build_allowed"
                # ;;

                # production:both:dam)
                # AEM_SERVERS="$prd_dam_aem_authors,$prd_dam_aem_publishers"
                # buildAllowed="production:$production_build_allowed"
                # ;;

                # all:both:dam)
                # AEM_SERVERS="$dev_dam_aem_authors,$dev_dam_aem_publishers,$stg_dam_aem_authors,$stg_dam_aem_publishers,$prd_dam_aem_authors,$prd_dam_aem_publishers"
                # buildAllowed="development:$dev_build_allowed,stage:$stage_build_allowed,production:$production_build_allowed"
                # ;;

                # dev:author:gen)
                # AEM_SERVERS=$dev_gen_aem63_authors
                # buildAllowed="development:$dev_build_allowed"
                # ;;

                # dev:publish:gen)
                # AEM_SERVERS=$dev_gen_aem63_publishers
                # buildAllowed="development:$dev_build_allowed"
                # ;;

                # dev:both:gen)
                # AEM_SERVERS="$dev_gen_aem63_authors,$dev_gen_aem63_publishers"
                # buildAllowed="development:$dev_build_allowed"
                # ;;

                # stage:author:gen)
                # AEM_SERVERS=$stg_gen_aem63_authors
                # buildAllowed="stage:$stage_build_allowed"
                # ;;

                # stage:publish:gen)
                # AEM_SERVERS=$stg_gen_aem63_publishers
                # buildAllowed="stage:$stage_build_allowed"
                # ;;

                # stage:both:gen)
                # AEM_SERVERS="$stg_gen_aem63_authors,$stg_gen_aem63_publishers"
                # buildAllowed="stage:$stage_build_allowed"
                # ;;

                # preview:publish:gen)
                # AEM_SERVERS=$prv_gen_aem63_publishers
                # buildAllowed="production:$production_build_allowed"
                # ;;

                # production:author:gen)
                # AEM_SERVERS=$prd_gen_aem63_authors
                # buildAllowed="production:$production_build_allowed"
                # ;;

                # production:publish:gen)
                # AEM_SERVERS=$prd_gen_aem63_publishers
                # buildAllowed="production:$production_build_allowed"
                # ;;

                # production:both:gen)
                # AEM_SERVERS="$prd_gen_aem63_authors,$prd_gen_aem63_publishers"
                # buildAllowed="production:$production_build_allowed"
                # ;;

                # all:both:gen)
                # AEM_SERVERS="$dev_gen_aem63_authors,$dev_gen_aem63_publishers,$stg_gen_aem63_authors,$stg_gen_aem63_publishers,$prd_gen_aem63_authors,$prd_gen_aem63_publishers"
                # buildAllowed="development:$dev_build_allowed,stage:$stage_build_allowed,production:$production_build_allowed"
                # ;;

                # dev:author:kstl)
                # AEM_SERVERS=$dev_kstl_aem_authors
                # buildAllowed="development:$dev_build_allowed"
                # ;;

                # dev:publish:kstl)
                # AEM_SERVERS=$dev_kstl_aem_publishers
                # buildAllowed="development:$dev_build_allowed"
                # ;;

                # dev:both:kstl)
                # AEM_SERVERS="$dev_kstl_aem_authors,$dev_kstl_aem_publishers"
                # buildAllowed="development:$dev_build_allowed"
                # ;;

                # stage:author:kstl)
                # AEM_SERVERS=$stg_kstl_aem_authors
                # buildAllowed="stage:$stage_build_allowed"
                # ;;

                # stage:publish:kstl)
                # AEM_SERVERS=$stg_kstl_aem_publishers
                # buildAllowed="stage:$stage_build_allowed"
                # ;;

                # stage:both:kstl)
                # AEM_SERVERS="$stg_kstl_aem_authors,$stg_kstl_aem_publishers"
                # buildAllowed="stage:$stage_build_allowed"
                # ;;

                # preview:publish:kstl)
                # AEM_SERVERS=$prv_kstl_aem_publishers
                # buildAllowed="production:$production_build_allowed"
                # ;;

                # production:author:kstl)
                # AEM_SERVERS=$prd_kstl_aem_authors
                # buildAllowed="production:$production_build_allowed"
                # ;;

                # production:publish:kstl)
                # AEM_SERVERS=$prd_kstl_aem_publishers
                # buildAllowed="production:$production_build_allowed"
                # ;;

                # production:both:kstl)
                # AEM_SERVERS="$prd_kstl_aem_authors,$prd_kstl_aem_publishers"
                # buildAllowed="production:$production_build_allowed"
                # ;;

                # all:both:kstl)
                # AEM_SERVERS="$dev_kstl_aem_authors,$dev_kstl_aem_publishers,$stg_kstl_aem_authors,$stg_kstl_aem_publishers,$prd_kstl_aem_authors,$prd_kstl_aem_publishers"
                # buildAllowed="development:$dev_build_allowed,stage:$stage_build_allowed,production:$production_build_allowed"
                # ;;

                # dev:author:kstl5)
                # AEM_SERVERS=$dev_kstl_aem63_authors
                # buildAllowed="development:$dev_build_allowed"
                # ;;

                # dev:publish:kstl5)
                # AEM_SERVERS=$dev_kstl_aem63_publishers
                # buildAllowed="development:$dev_build_allowed"
                # ;;

                # dev:both:kstl5)
                # AEM_SERVERS="$dev_kstl_aem63_authors,$dev_kstl_aem63_publishers"
                # buildAllowed="development:$dev_build_allowed"
                # ;;

                # stage:author:kstl5)
                # AEM_SERVERS=$stg_kstl_aem63_authors
                # buildAllowed="stage:$stage_build_allowed"
                # ;;

                # stage:publish:kstl5)
                # AEM_SERVERS=$stg_kstl_aem63_publishers
                # buildAllowed="stage:$stage_build_allowed"
                # ;;

                # stage:both:kstl5)
                # AEM_SERVERS="$stg_kstl_aem63_authors,$stg_kstl_aem63_publishers"
                # buildAllowed="stage:$stage_build_allowed"
                # ;;

                # preview:publish:kstl5)
                # AEM_SERVERS=$prv_kstl_aem63_publishers
                # buildAllowed="production:$production_build_allowed"
                # ;;

                # production:author:kstl5)
                # AEM_SERVERS=$prd_kstl_aem63_authors
                # buildAllowed="production:$production_build_allowed"
                # ;;

                # production:publish:kstl5)
                # AEM_SERVERS=$prd_kstl_aem63_publishers
                # buildAllowed="production:$production_build_allowed"
                # ;;

                # production:both:kstl5)
                # AEM_SERVERS="$prd_kstl_aem63_authors,$prd_kstl_aem63_publishers"
                # buildAllowed="production:$production_build_allowed"
                # ;;

                # all:both:kstl5)
                # AEM_SERVERS="$dev_kstl_aem63_authors,$dev_kstl_aem63_publishers,$stg_kstl_aem63_authors,$stg_kstl_aem63_publishers,$prd_kstl_aem63_authors,$prd_kstl_aem63_publishers"
                # buildAllowed="development:$dev_build_allowed,stage:$stage_build_allowed,production:$production_build_allowed"
                # ;;

                # dev:author:kstl65)
                # AEM_SERVERS=$dev_kstl_aem65_authors
                # buildAllowed="development:$dev_build_allowed"
                # ;;

                # dev:publish:kstl65)
                # AEM_SERVERS=$dev_kstl_aem65_publishers
                # buildAllowed="development:$dev_build_allowed"
                # ;;

                # dev:both:kstl65)
                # AEM_SERVERS="$dev_kstl_aem65_authors,$dev_kstl_aem65_publishers"
                # buildAllowed="development:$dev_build_allowed"
                # ;;

                # stage:author:kstl65)
                # AEM_SERVERS=$stg_kstl_aem65_authors
                # buildAllowed="stage:$stage_build_allowed"
                # ;;

                # stage:publish:kstl65)
                # AEM_SERVERS=$stg_kstl_aem65_publishers
                # buildAllowed="stage:$stage_build_allowed"
                # ;;

                # stage:both:kstl65)
                # AEM_SERVERS="$stg_kstl_aem65_authors,$stg_kstl_aem65_publishers"
                # buildAllowed="stage:$stage_build_allowed"
                # ;;

                # production:author:kstl65)
                # AEM_SERVERS=$prd_kstl_aem65_authors
                # buildAllowed="production:$production_build_allowed"
                # ;;

                # production:publish:kstl65)
                # AEM_SERVERS=$prd_kstl_aem65_publishers
                # buildAllowed="production:$production_build_allowed"
                # ;;

                # production:both:kstl65)
                # AEM_SERVERS="$prd_kstl_aem65_authors,$prd_kstl_aem65_publishers"
                # buildAllowed="production:$production_build_allowed"
                # ;;

                # all:both:kstl65)
                # AEM_SERVERS="$dev_kstl_aem65_authors,$dev_kstl_aem65_publishers,$stg_kstl_aem65_authors,$stg_kstl_aem65_publishers,$prd_kstl_aem65_authors,$prd_kstl_aem65_publishers"
                # buildAllowed="development:$dev_build_allowed,stage:$stage_build_allowed,production:$production_build_allowed"
                # ;;

                # dev:author:newkstl65)
                # AEM_SERVERS=$dev_kstl_aemkstl65_authors
                # buildAllowed="development:$dev_build_allowed"
                # ;;

                # dev:publish:newkstl65)
                # AEM_SERVERS=$dev_kstl_aemkstl65_publishers
                # buildAllowed="development:$dev_build_allowed"
                # ;;

                # dev:both:newkstl65)
                # AEM_SERVERS="$dev_kstl_aemkstl65_authors,$dev_kstl_aemkstl65_publishers"
                # buildAllowed="development:$dev_build_allowed"
                # ;;

                # stage:author:newkstl65)
                # AEM_SERVERS=$stg_kstl_aemkstl65_authors
                # buildAllowed="stage:$stage_build_allowed"
                # ;;

                # stage:publish:newkstl65)
                # AEM_SERVERS=$stg_kstl_aemkstl65_publishers
                # buildAllowed="development:$stage_build_allowed"
                # ;;

                # stage:both:newkstl65)
                # AEM_SERVERS="$stg_kstl_aemkstl65_authors,$stg_kstl_aemkstl65_publishers"
                # buildAllowed="stage:$stage_build_allowed"
                # ;;

                # production:author:newkstl65)
                # AEM_SERVERS=$prd_kstl_aemkstl65_authors
                # buildAllowed="production:$production_build_allowed"
                # ;;

                # production:publish:newkstl65)
                # AEM_SERVERS=$prd_kstl_aemkstl65_publishers
                # buildAllowed="production:$production_build_allowed"
                # ;;

                # production:both:newkstl65)
                # AEM_SERVERS="$prd_kstl_aemkstl65_authors,$prd_kstl_aemkstl65_publishers"
                # buildAllowed="production:$production_build_allowed"
                # ;;

                # all:both:newkstl65)
                # AEM_SERVERS="$dev_kstl_aemkstl65_authors,$dev_kstl_aemkstl65_publishers,$stg_kstl_aemkstl65_authors,$stg_kstl_aemkstl65_publishers,$prd_kstl_aemkstl65_authors,$prd_kstl_aemkstl65_publishers"
                # buildAllowed="development:$dev_build_allowed,stage:$stage_build_allowed,production:$production_build_allowed"
                # ;;

                # dev:author:kfr)
                # AEM_SERVERS=$dev_kfr_aem_authors
                # buildAllowed="development:$dev_build_allowed"
                # ;;

                # dev:publish:kfr)
                # AEM_SERVERS=$dev_kfr_aem_publishers
                # buildAllowed="development:$dev_build_allowed"
                # ;;

                # dev:both:kfr)
                # AEM_SERVERS="$dev_kfr_aem_authors,$dev_kfr_aem_publishers"
                # buildAllowed="development:$dev_build_allowed"
                # ;;

                # stage:author:kfr)
                # AEM_SERVERS=$stg_kfr_aem_authors
                # buildAllowed="stage:$stage_build_allowed"
                # ;;

                # stage:publish:kfr)
                # AEM_SERVERS=$stg_kfr_aem_publishers
                # buildAllowed="stage:$stage_build_allowed"
                # ;;

                # stage:both:kfr)
                # AEM_SERVERS="$stg_kfr_aem_authors,$stg_kfr_aem_publishers"
                # buildAllowed="stage:$stage_build_allowed"
                # ;;

                # preview:publish:kfr)
                # AEM_SERVERS=$prv_kfr_aem_publishers
                # buildAllowed="production:$production_build_allowed"
                # ;;

                # production:author:kfr)
                # AEM_SERVERS=$prd_kfr_aem_authors
                # buildAllowed="production:$production_build_allowed"
                # ;;

                # production:publish:kfr)
                # AEM_SERVERS=$prd_kfr_aem_publishers
                # buildAllowed="production:$production_build_allowed"
                # ;;

                # production:both:kfr)
                # AEM_SERVERS="$prd_kfr_aem_authors,$prd_kfr_aem_publishers"
                # buildAllowed="production:$production_build_allowed"
                # ;;

                # all:both:kfr)
                # AEM_SERVERS="$dev_kfr_aem_authors,$dev_kfr_aem_publishers,$stg_kfr_aem_authors,$stg_kfr_aem_publishers,$prd_kfr_aem_authors,$prd_kfr_aem_publishers"
                # buildAllowed="development:$dev_build_allowed,stage:$stage_build_allowed,production:$production_build_allowed"
                # ;;

                # dev:author:kfr63)
                # AEM_SERVERS=$dev_kfr_aem63_authors
                # buildAllowed="development:$dev_build_allowed"
                # ;;

                # dev:publish:kfr63)
                # AEM_SERVERS=$dev_kfr_aem63_publishers
                # buildAllowed="development:$dev_build_allowed"
                # ;;

                # dev:both:kfr63)
                # AEM_SERVERS="$dev_kfr_aem63_authors,$dev_kfr_aem63_publishers"
                # buildAllowed="development:$dev_build_allowed"
                # ;;

                # stage:author:kfr63)
                # AEM_SERVERS=$stg_kfr_aem63_authors
                # buildAllowed="stage:$stage_build_allowed"
                # ;;

                # stage:publish:kfr63)
                # AEM_SERVERS=$stg_kfr_aem63_publishers
                # buildAllowed="stage:$stage_build_allowed"
                # ;;

                # stage:both:kfr63)
                # AEM_SERVERS="$stg_kfr_aem63_authors,$stg_kfr_aem63_publishers"
                # buildAllowed="stage:$stage_build_allowed"
                # ;;

                # preview:publish:kfr63)
                # AEM_SERVERS=$prv_kfr_aem63_publishers
                # buildAllowed="production:$production_build_allowed"
                # ;;

                # production:author:kfr63)
                # AEM_SERVERS=$prd_kfr_aem63_authors
                # buildAllowed="production:$production_build_allowed"
                # ;;

                # production:publish:kfr63)
                # AEM_SERVERS=$prd_kfr_aem63_publishers
                # buildAllowed="production:$production_build_allowed"
                # ;;

                # production:both:kfr63)
                # AEM_SERVERS="$prd_kfr_aem63_authors,$prd_kfr_aem63_publishers"
                # buildAllowed="production:$production_build_allowed"
                # ;;

                # all:both:kfr63)
                # AEM_SERVERS="$dev_kfr_aem63_authors,$dev_kfr_aem63_publishers,$stg_kfr_aem63_authors,$stg_kfr_aem63_publishers,$prd_kfr_aem63_authors,$prd_kfr_aem63_publishers"
                # buildAllowed="development:$dev_build_allowed,stage:$stage_build_allowed,production:$production_build_allowed"
                # ;;

                                # dev:author:kfr65)
                # AEM_SERVERS=$dev_kfr_aemkfr65_authors
                # buildAllowed="development:$dev_build_allowed"
                # ;;

                # dev:publish:kfr65)
                # AEM_SERVERS=$dev_kfr_aemkfr65_publishers
                # buildAllowed="development:$dev_build_allowed"
                # ;;

                # dev:both:kfr65)
                # AEM_SERVERS="$dev_kfr_aemkfr65_authors,$dev_kfr_aemkfr65_publishers"
                # buildAllowed="development:$dev_build_allowed"
                # ;;

                # all:both:kfr65)
                # AEM_SERVERS="$dev_kfr_aemkfr65_authors,$dev_kfr_aemkfr65_publishers"
                # buildAllowed="development:$dev_build_allowed"
                # ;;


                # stage:author:kfr65)
                # AEM_SERVERS=$stg_kfr_aemkfr65_authors
                # buildAllowed="stage:$stage_build_allowed"
                # ;;

                # stage:publish:kfr65)
                # AEM_SERVERS=$stg_kfr_aemkfr65_publishers
                # buildAllowed="stage:$stage_build_allowed"
                # ;;

                # stage:both:kfr65)
                # AEM_SERVERS="$stg_kfr_aemkfr65_authors,$stg_kfr_aemkfr65_publishers"
                # buildAllowed="stage:$stage_build_allowed"
                # ;;

                        # stage:author:kfr65)
                # AEM_SERVERS=$stg_kfr_aemkfr65_authors
                # buildAllowed="stage:$stage_build_allowed"
                # ;;

                # stage:publish:kfr65)
                # AEM_SERVERS=$stg_kfr_aemkfr65_publishers
                # buildAllowed="stage:$stage_build_allowed"
                # ;;

                # stage:both:kfr65)
                # AEM_SERVERS="$stg_kfr_aemkfr65_authors,$stg_kfr_aemkfr65_publishers"
                # buildAllowed="stage:$stage_build_allowed"
                # ;;

                # uatkfr:author:kfr65)
                # AEM_SERVERS=$uat_kfr_aemkfr65_authors
                # buildAllowed="uatkfr:$uatkfr_build_allowed"
                # ;;

                # uatkfr:publish:kfr65)
                # AEM_SERVERS=$uat_kfr_aemkfr65_publishers
                # buildAllowed="uatkfr:$uatkfr_build_allowed"
                # ;;

                # uatkfr:both:kfr65)
                # AEM_SERVERS="$uat_kfr_aemkfr65_authors,$uat_kfr_aemkfr65_publishers"
                # buildAllowed="uatkfr:$uatkfr_build_allowed"
                # ;;

                # production:author:kfr65)
                # AEM_SERVERS=$prd_kfr_aemkfr65_authors
                # buildAllowed="production:$production_build_allowed"
                # ;;

                # production:publish:kfr65)
                # AEM_SERVERS=$prd_kfr_aemkfr65_publishers
                # buildAllowed="production:$production_build_allowed"
                # ;;

                # production:both:kfr65)
                # AEM_SERVERS="$prd_kfr_aemkfr65_authors,$prd_kfr_aemkfr65_publishers"
                # buildAllowed="production:$production_build_allowed"
                # ;;

                # *)
                # echo "Combination not identified $servereval, if using all option, ensure you also chose both option."
                # exit
                # ;;
        # esac

        # echo "Selected server values $AEM_SERVERS"

        # #check if build allowed is true
        # AEM_BUILD_PERMITED=`echo $buildAllowed|sed 's/,/ /g'`
        # for AEM_BUILD_PERMIT in $AEM_BUILD_PERMITED
        # do
                # if [[ $AEM_BUILD_PERMIT == *"true"* ]]; then
                        # buildenv=`echo $AEM_BUILD_PERMIT | awk -F':' '{print $1}'`
                        # echo "$buildenv builds enabled"
                # else
                        # buildenv=`echo $AEM_BUILD_PERMIT | awk -F':' '{print $1}'`
                        # echo "$buildenv builds disabled"
                        # exit 1
                # fi
        # done

        # echo "Installation of $jarfileloc starting for $instance instances in $environment for ${pool}."
        # # Replace the comma with a space to setup the array
        # AEM_DEPLOYS=`echo $AEM_SERVERS|sed 's/,/ /g'`

        # # Loop through the array of IP:PORT:USERNAME:PASSWORD server variables
        # for AEM_DEPLOY in $AEM_DEPLOYS
        # do
                # AEM_DEPLOY_IP=`echo $AEM_DEPLOY | awk -F':' '{print $1}'`
                # AEM_DEPLOY_PORT=`echo $AEM_DEPLOY | awk -F':' '{print $2}'`
                # echo $AEM_DEPLOY_IP
        # done
        # AEM_DEPLOY_USERNAME=`echo $aem_build_user | awk -F':' '{print $1}'`
        # AEM_DEPLOY_PASSWORD=`echo $aem_build_user | awk -F':' '{print $2}'`

        # #check filter specification
        # explodePathRoot="/var/lib/build/workspace/$group/$project"
        # explodePath="$explodePathRoot/temp"
        # cd $explodePath
        # echo `pwd`
        # if $bZip ; then
                # zipVal= unzip -o $jarfileloc META-INF/vault/filter.xml -d $explodePath
                # zipPropFile= unzip -o $jarfileloc META-INF/vault/properties.xml -d $explodePath
                # echo $zipVal
        # else
                # jarVal= jar xvf $jarfileloc META-INF/vault/filter.xml -c $explodePath
                # jarPropFile= jar xvf $jarfileloc META-INF/vault/properties.xml -c $explodePath
                # echo $jarVal
        # fi
        # echo "filtered paths:"
        # cat $explodePathRoot/filter.txt
        # echo ""
        # propfile=$explodePath/META-INF/vault/properties.xml
        # while read i; do
                # if [[ $i == *name* ]]; then
                        # propname=`echo $i | cut -f2 -d">"|cut -f1 -d"<"`
                # fi
        # done <$propfile
        # echo "properties xml name key:" $propname

        # #execute build
        # if $bDebug; then
                # # Loop through the List of IP:PORT:USERNAME:PASSWORD
                # for AEM_DEPLOY in $AEM_DEPLOYS
                # do
                        # AEM_DEPLOY_IP=`echo $AEM_DEPLOY | awk -F':' '{print $1}'`
                        # AEM_DEPLOY_PORT=`echo $AEM_DEPLOY | awk -F':' '{print $2}'`
                        # /usr/bin/curl -u $AEM_DEPLOY_USERNAME:$AEM_DEPLOY_PASSWORD -F name=$package -F file=@$jarfileloc http://$AEM_DEPLOY_IP:$AEM_DEPLOY_PORT/crx/packmgr/service.jsp
                        # list_packages """$propname""" $explodePathRoot/worker
                        # echo ""
                        # echo "Installing package $path$propname$version.zip"
                        # echo ""
                        # result=`/usr/bin/curl -u $AEM_DEPLOY_USERNAME:$AEM_DEPLOY_PASSWORD -X POST http://$AEM_DEPLOY_IP:$AEM_DEPLOY_PORT/crx/packmgr/service/*.json$path$package.zip?cmd=install`
                        # get_fn_results "install"
                # done
                # rm -rf $explodePath/META-INF
                # exit 0
        # else
                # echo "evaluating filter: "
                # pfilter=${explodePath}/META-INF/vault/filter.xml
                # cat $pfilter
                # echo ""
                # result=$(validateFilter $explodePath $group $project )
                # if [ $result = 1 ]; then
                        # echo "Filters match, proceeding to install..."
                        # # Loop through the List of IP:PORT:USERNAME:PASSWORD
                        # for AEM_DEPLOY in $AEM_DEPLOYS
                        # do
                                # AEM_DEPLOY_IP=`echo $AEM_DEPLOY | awk -F':' '{print $1}'`
                                # AEM_DEPLOY_PORT=`echo $AEM_DEPLOY | awk -F':' '{print $2}'`
                                # echo "uploading package $package"
                                # cmdt=`/usr/bin/curl -u $AEM_DEPLOY_USERNAME:$AEM_DEPLOY_PASSWORD -F name=$package -F file=@$jarfileloc http://$AEM_DEPLOY_IP:$AEM_DEPLOY_PORT/crx/packmgr/service.jsp`
                                # echo "setting property name for package $propname"
                                # list_packages """$propname""" $explodePath/META-INF/worker
                                # if [ -z "$version" ]; then
                                        # echo ""
                                        # echo "Installing package $path$propname.zip"
                                        # echo ""
                                        # pkg=$path$propname
                                        # pkg=${pkg// /%20}
                                        # result=`/usr/bin/curl -u $AEM_DEPLOY_USERNAME:$AEM_DEPLOY_PASSWORD -X POST http://$AEM_DEPLOY_IP:$AEM_DEPLOY_PORT/crx/packmgr/service/*.json$pkg.zip?cmd=install&force=true&recursive=true`
                                        # get_fn_results "install"
                                # else
                                        # echo ""
                                        # echo "Installing package $path$propname-$version.zip"
                                        # echo ""
                                        # pkg=$path$propname-$version
                                        # pkg=${pkg// /%20}
                                        # result=`/usr/bin/curl -u $AEM_DEPLOY_USERNAME:$AEM_DEPLOY_PASSWORD -X POST http://$AEM_DEPLOY_IP:$AEM_DEPLOY_PORT/crx/packmgr/service/*.json$pkg.zip?cmd=install&force=true&recursive=true`
                                        # get_fn_results "install"
                                # fi
                        # done
                        # rm -rf $explodePath/META-INF
                        # exit 0
                # else
                        # echo "Filters do no match, please review package and filter specification."
                        # rm -rf $explodePath/META-INF
                        # exit 1
                # fi
        # fi
# }

# #setup input variables
# if [ -z "$inputpath" ]; then
        # inputpath=$1
        # if [[ $inputpath != *\/ ]]; then
                # inputpath=$inputpath"/"
        # fi
# fi

# if [ -z "$package" ]; then
        # package=$2
# fi

# if [ -z "$group" ]; then
        # group=$3
# fi

# if [ -z "$project" ]; then
        # project=$4
# fi

# # Define the lines to add for creating 'temp' folder and 'filter.txt' file
# # Ensure the temp folder exists
# mkdir -p /var/lib/build/workspace/$group/$project/temp

# # Create filter.txt with '/' as its content if it doesn't exist
# if [ ! -f /var/lib/build/workspace/$group/$project/filter.txt ]; then
    # echo '/' > /var/lib/build/workspace/$group/$project/filter.txt
# fi
# # Insert the additional lines at the appropriate location in the script #

# if [ -z "$environment" ]; then
        # environment=$5
# fi

# if [ -z "$instance" ]; then
        # instance=$6
# fi

# if [ -z "$pool" ]; then
        # pool=$7
# fi

# if [[ $8 == "debug" ]]; then
        # bDebug="true"
# else
        # bDebug="false"
# fi

# if [[ $1 == "--help" ]] || [[ $1 == "-h" ]] || [[ $1 == "-help" ]] || [[ $1 == "-hlep" ]]; then
        # help
# elif [ `echo $@ | wc -w` -eq 7 ]; then
        # main $inputpath $package $group $project $environment $instance $pool $bDebug
# elif [ `echo $@ | wc -w` -eq 8 ]; then
        # main $inputpath $package $group $project $environment $instance $pool $bDebug
# else
        # help
# fi
