#!/usr/bin/env bash

source TYPO3.conf

if [ ! -d ${SOURCES}/.git ]; then
	rm -rf ${SOURCES}
	mkdir -p ${SOURCES}
	pushd ${SOURCES} >/dev/null
	git clone ${GIT} .
	popd >/dev/null
fi

if [ -d ${TARGET} ]; then
	mkdir -p ${TARGET}
fi

# Update TYPO3 sources
pushd ${SOURCES} >/dev/null
git checkout master
git reset --hard origin/master
git fetch
popd >/dev/null

for VERSION in "${!BRANCHES[@]}"; do
	# Switch to corresponding TYPO3 branch
	pushd ${SOURCES} >/dev/null
	git checkout ${BRANCHES[$VERSION]}
	popd >/dev/null
	
	pushd ${SOURCES}/typo3/sysext/ >/dev/null

	SYSTEM_EXTENSIONS=$(find . -type d -maxdepth 1 | cut -b3-)
	for EXTENSION in ${SYSTEM_EXTENSIONS}; do
	
		if [ $(find ${EXTENSION} -name \*.xlf | wc -l) -eq 0 ]; then
			continue
		fi
	
		mkdir -p ${TARGET}/TYPO3.TYPO3.core.${EXTENSION}
	
		pushd ${EXTENSION} >/dev/null
		EXTENSION_TARGET=${TARGET}/TYPO3.TYPO3.core.${EXTENSION}
		MAPPING=${EXTENSION_TARGET}/.typo3/${VERSION}.filemapping
	
		mkdir -p ${EXTENSION_TARGET}/.typo3
		mkdir -p ${EXTENSION_TARGET}/templates
		rm -f ${MAPPING}
		touch ${MAPPING}
	
		FILES=$(find . -name \*.xlf);
		for FILE in ${FILES}; do
			T3ID=$(xmlstarlet sel -t -m "//xliff/file" -v "@t3:id" ${FILE} 2>/dev/null)
			if [ -z "${T3ID}" ]; then
				continue
			fi
	
			TARGET_NAME=${EXTENSION_TARGET}/templates/locallang.${T3ID}.xlf
			cp $FILE ${TARGET_NAME}
			echo "locallang.${T3ID}.xlf ${FILE}" >> ${MAPPING}
	
			KEYS=${EXTENSION_TARGET}/.typo3/${VERSION}.${T3ID}.keys
			xmlstarlet sel -t -m "//xliff/file/body/trans-unit" -v "@id" -n ${FILE} | sort > ${KEYS}
		done
	
		popd >/dev/null
	done
	
	popd >/dev/null
done
