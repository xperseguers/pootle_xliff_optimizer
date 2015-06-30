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

BRANCHES_INDEXES=( ${!BRANCHES[@]} )
IFS=$'\n' VERSIONS=$(echo -e "${BRANCHES_INDEXES[@]/%/\\n}" | sed -e 's/^ *//' -e '/^$/d' | sort)
for VERSION in ${VERSIONS}; do
	# Switch to corresponding TYPO3 branch
	pushd ${SOURCES} >/dev/null
	git checkout ${BRANCHES[$VERSION]}
	git pull
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
			echo "locallang.${T3ID}.xlf ${FILE}" >> ${MAPPING}
	
			KEYS=${EXTENSION_TARGET}/.typo3/${VERSION}.${T3ID}.keys
			xmlstarlet sel -t -m "//xliff/file/body/trans-unit" -v "@id" -n ${FILE} | sort > ${KEYS}

			if [ -f "${TARGET_NAME}" ]; then
				# Extract existing keys
				xmlstarlet sel -t -m "//xliff/file/body/trans-unit" -v "@id" -n ${TARGET_NAME} | sort > /tmp/existing.keys

				diff -q ${KEYS} /tmp/existing.keys >/dev/null
				if [ $? -eq 1 ]; then
					# Preparing new XLIFF
					cat ${TARGET_NAME} | grep -v "</xliff>" | grep -v "</file>" | grep -v "</body>" > ${TARGET_NAME}.tmp

					NEW_KEYS=$(diff /tmp/existing.keys ${KEYS} | grep '^> ' | cut -b3-)
					for NEW_KEY in ${NEW_KEYS}; do
						echo -en "\t\t\t" >> ${TARGET_NAME}.tmp
						xmlstarlet sel -t -c "//trans-unit[@id='${NEW_KEY}']" ${FILE} | sed -e 's/ xmlns:t3="[^"]*"//g' >> ${TARGET_NAME}.tmp
					done

					echo -e "\t\t</body>" >> ${TARGET_NAME}.tmp
					echo -e "\t</file>" >> ${TARGET_NAME}.tmp
					echo '</xliff>' >> ${TARGET_NAME}.tmp

					mv ${TARGET_NAME}.tmp ${TARGET_NAME}
					# TODO: deprecated stuff as Pootle note
					# TODO: override label for existing key if it was changed (tolerated with some restrictions)
				fi
			else
				# File did not exist
				cp ${FILE} ${TARGET_NAME}
			fi
		done
	
		popd >/dev/null
	done
	
	popd >/dev/null
done
