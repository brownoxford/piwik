#!/bin/bash
# Syntax: build.sh version|'nightly'|'webtest'

VERSION="$1"
DEST_PATH=/home/piwik/builds
URL_REPO=https://github.com/piwik/piwik.git
HTTP_PATH=/home/piwik/www/builds.piwik.org

# report error and exit
function die() {
	echo -e "$0: $1"
	exit 2
}

# clean up the workspace
function cleanupWorkspace() {
	rm -rf piwik
	rm -f *.html
	rm -f *.xml
	rm -f *.sql
}

# organize files for packaging
function organizePackage() {
	rm -rf piwik/libs/PhpDocumentor-1.3.2/
	rm -rf piwik/libs/FirePHPCore/
	rm -f piwik/libs/open-flash-chart/php-ofc-library/ofc_upload_image.php

	rm -rf piwik/tmp/*
	rm -f piwik/misc/db-schema*
	rm -f piwik/misc/diagram_general_request*

	cp piwik/tests/README.txt .
	find piwik -name 'tests' -type d -prune -exec rm -rf {} \;
	mkdir piwik/tests
	mv README.txt piwik/tests/

	cp piwik/misc/How\ to\ install\ Piwik.html .
	if [ -e piwik/misc/package ]; then
		cp piwik/misc/package/WebAppGallery/*.* .
		rm -rf piwik/misc/package/
	else
		if [ -e piwik/misc/WebAppGallery ]; then
			cp piwik/misc/WebAppGallery/*.* .
			rm -rf piwik/misc/WebAppGallery
		fi
	fi

	find piwik -type f -printf '%s ' -exec md5sum {} \; | fgrep -v 'manifest.inc.php' | sed '1,$ s/\([0-9]*\) \([a-z0-9]*\) *piwik\/\(.*\)/\t\t"\3" => array("\1", "\2"),/;' | sort | sed '1 s/^/<?php\n\/\/ This file is automatically generated during the Piwik build process\nclass Manifest {\n\tstatic $files=array(\n/; $ s/$/\n\t);\n}/' > piwik/config/manifest.inc.php
}

if [ -z "$VERSION" ]; then
	die "Expected a version number, 'nightly', or 'webtest' as a parameter"
fi

case "$VERSION" in
	"nightly" )
		if [ ! -e "${WORKSPACE}/trunk" ]; then
			die "Piwik trunk not present!"
		fi

		cleanupWorkspace
		rm -f latest.zip

		cp -R trunk piwik
		find piwik -name '.git' -type d -prune -exec rm -rf {} \;

		organizePackage

		zip -q -r latest.zip piwik How\ to\ install\ Piwik.html *.xml *.sql > /dev/null 2> /dev/null
		;;
	"webtest" )
		if [ ! -e "${WORKSPACE}/build/core/Version.php" ]; then
			die "Piwik source files not present!"
		fi

		cleanupWorkspace
		rm -rf 1.0
		rm -f latest.zip

		cp -R build piwik
		find piwik -name '.git' -type d -prune -exec rm -rf {} \;

		organizePackage

		zip -q -r latest.zip piwik > /dev/null 2> /dev/null

		# Set-up infrastructure proxies for testing
		LATESTVERSION=`fgrep VERSION build/core/Version.php  | sed -e "s/\tconst VERSION = '//" | sed -e "s/'.*//"`
		mkdir 1.0
		mkdir 1.0/getLatestVersion
		cat >1.0/getLatestVersion/index.php <<GET_LATEST_VERSION
<?php
	echo "${LATESTVERSION}";
GET_LATEST_VERSION

		mkdir 1.0/subscribeNewsletter
		cat >1.0/subscribeNewsletter/index.php <<SUBSCRIBE_NEWSLETTER
<?php
	echo "ok";
SUBSCRIBE_NEWSLETTER
		;;
	* )
		if [ ! -e $DEST_PATH ] ; then
			echo "Destination directory does not exist... Creating it!";
			mkdir -p $DEST_PATH;
		fi

		cd $DEST_PATH
		cleanupWorkspace

		echo "checkout repository for tag $VERSION"
		rm -rf $DEST_PATH/piwik_last_version
		git clone -q -- $URL_REPO $DEST_PATH/piwik_last_version || die "Problem checking out the last version tag"
		cd $DEST_PATH/piwik_last_version
		git checkout tags/$VERSION -q

		cd $DEST_PATH
		echo "preparing release $VERSION"

		mv piwik_last_version piwik
		echo `grep "'$VERSION'" piwik/core/Version.php`
		if [ `grep "'$VERSION'" piwik/core/Version.php | wc -l` -ne 1 ]; then
			echo "version $VERSION does not match core/Version.php";
			exit
		fi

		echo "organizing files and writing manifest file..."
		organizePackage

		echo "packaging release..."
		zip -r piwik-$VERSION.zip piwik How\ to\ install\ Piwik.html > /dev/null 2> /dev/null
		tar -czf piwik-$VERSION.tar.gz piwik How\ to\ install\ Piwik.html
		mv piwik-$VERSION.{zip,tar.gz} $HTTP_PATH

		zip -r piwik-$VERSION-WAG.zip piwik *.xml *.sql > /dev/null 2> /dev/null
		mv piwik-$VERSION-WAG.zip $HTTP_PATH/WebAppGallery/piwik-$VERSION.zip

		if [ `echo $VERSION | grep -E 'rc|b|a|alpha|beta|dev' -i | wc -l` -eq 1 ]; then
			echo "Beta or RC release";
			echo $VERSION > $HTTP_PATH/LATEST_BETA
			echo "build finished! http://builds.piwik.org/piwik-$VERSION.zip"
		else
			echo "Stable release";

			#hard linking piwik.org/latest.zip to the newly created build
			for i in zip tar.gz; do
				ln -sf $HTTP_PATH/piwik-$VERSION.$i $HTTP_PATH/latest.$i
			done

			echo $VERSION > $HTTP_PATH/LATEST
			echo $VERSION > $HTTP_PATH/LATEST_BETA
			echo "build finished! http://piwik.org/latest.zip"
		fi
	;;
esac

cleanupWorkspace
