#!/usr/bin/env bash

source ../TYPO3.conf

if [ ! -d ${SOURCES}/.git ]; then
	echo "[INIT]    Cloning TYPO3 CMS sources into ${SOURCES}"
	rm -rf ${SOURCES}
	mkdir -p ${SOURCES}
	pushd ${SOURCES} >/dev/null
	git clone ${GIT} . >/dev/null 2>&1
	popd >/dev/null
fi

for BRANCH in master TYPO3_6-2; do
	echo "[INFO]    Looking for duplicate labels in ${BRANCH}"
	pushd ${SOURCES} >/dev/null
	git checkout ${BRANCH} >/dev/null 2>&1
	popd >/dev/null

	pushd ${SOURCES}/typo3/sysext/ >/dev/null

	SYSTEM_EXTENSIONS=$(find . -type d -maxdepth 1 | cut -b3-)
	for EXTENSION in ${SYSTEM_EXTENSIONS}; do
		echo "[INFO]    Analyzing EXT:${EXTENSION}"

		if [ $(find ${EXTENSION} -name \*.xlf | wc -l) -eq 0 ]; then
			continue
		fi

		FILES=$(find ${EXTENSION} -name \*.xlf);
		for FILE in ${FILES}; do
			xmlstarlet sel -t -m "//trans-unit" -v "@id" -n ${FILE} | sort > /tmp/${EXTENSION}.keys
			cat /tmp/${EXTENSION}.keys | sort -u > /tmp/${EXTENSION}.keys.sorted
			diff -q /tmp/${EXTENSION}.keys /tmp/${EXTENSION}.keys.sorted >/dev/null
			if [ $? -eq 1 ]; then
				echo "[WARNING]   ${FILE}"
				DUPLICATES=$(diff /tmp/${EXTENSION}.keys /tmp/${EXTENSION}.keys.sorted | grep '^< ' | cut -b3-)
				for D in ${DUPLICATES}; do
					echo "[WARNING]     - Duplicate key: ${D}"
				done
			fi

			rm -f /tmp/${EXTENSION}.keys /tmp/${EXTENSION}.keys.sorted
		done
	done
	
	popd >/dev/null
done
