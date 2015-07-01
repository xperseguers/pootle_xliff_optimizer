#!/usr/bin/env bash

source TYPO3.conf

if [ ! -d ${SOURCES}/.git ]; then
	echo "[INIT]    Cloning TYPO3 CMS sources into ${SOURCES}"
	rm -rf ${SOURCES}
	mkdir -p ${SOURCES}
	pushd ${SOURCES} >/dev/null
	git clone ${GIT} . >/dev/null 2>&1
	popd >/dev/null
fi

if [ -d ${TARGET} ]; then
	mkdir -p ${TARGET}
fi

# Update TYPO3 sources
echo "[INFO]    Fetching latest changes from TYPO3 CMS sources"
pushd ${SOURCES} >/dev/null
git checkout master >/dev/null 2>&1
git reset --hard origin/master >/dev/null 2>&1
git fetch >/dev/null 2>&1
popd >/dev/null

BRANCHES_INDEXES=( ${!BRANCHES[@]} )
IFS=$'\n' VERSIONS=$(echo -e "${BRANCHES_INDEXES[@]/%/\\n}" | sed -e 's/^ *//' -e '/^$/d' | sort)
for VERSION in ${VERSIONS}; do
	# Switch to corresponding TYPO3 branch
	echo "[INFO]    ------------------------------------------------------"
	echo "[INFO]    Switching to ${VERSION}"
	echo "[INFO]    ------------------------------------------------------"
	pushd ${SOURCES} >/dev/null
	git checkout ${BRANCHES[$VERSION]} >/dev/null 2>&1
	git pull >/dev/null 2>&1
	popd >/dev/null

	pushd ${SOURCES}/typo3/sysext/ >/dev/null

	SYSTEM_EXTENSIONS=$(find . -type d -maxdepth 1 | cut -b3-)
	for EXTENSION in ${SYSTEM_EXTENSIONS}; do
		echo "[INFO]    Updating XLIFF for EXT:${EXTENSION}"

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
			xmlstarlet sel -t -m "//trans-unit" -v "@id" -n ${FILE} | sort > ${KEYS}

			if [ -f "${TARGET_NAME}" ]; then
				DIRTY=0

				# Extract existing keys
				xmlstarlet sel -t -m "//trans-unit" -v "@id" -n ${TARGET_NAME} | sort > /tmp/existing.keys

				diff -q ${KEYS} /tmp/existing.keys >/dev/null
				if [ $? -eq 1 ]; then
					# START: Preparing new XLIFF
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
					# END: Preparing new XLIFF

					REMOVED_KEYS=$(diff /tmp/existing.keys ${KEYS} | grep '^< ' | cut -b3-)
					for REMOVED_KEY in ${REMOVED_KEYS}; do
						# Look for existing deprecation note
						NOTE=$(xmlstarlet sel -t -m "//trans-unit[@id='${REMOVED_KEY}']" -v "note[@from='developer']" ${TARGET_NAME})
						if [ -z "${NOTE}" ]; then
							# The label is not yet marked as "deprecated", do it now!
							xmlstarlet ed \
								-s "//trans-unit[@id='${REMOVED_KEY}']" \
								-t elem -n note -v "This label is deprecated (not used anymore) since ${VERSION}" \
								-i "//trans-unit[@id='${REMOVED_KEY}']/note" -t attr -n from -v developer ${TARGET_NAME} > ${TARGET_NAME}.tmp
							mv ${TARGET_NAME}.tmp ${TARGET_NAME}
						fi
					done

					DIRTY=1
				fi

				# Remove temporary file
				rm -f /tmp/existing.keys

				# Loop over all keys in file and update source element if needed (this is tolerated with some restrictions)
				for KEY in $(cat ${KEYS}); do
					CURRENT_VALUE=$(xmlstarlet sel -t -c "//trans-unit[@id='${KEY}']" ${TARGET_NAME} | sed -e 's/ xmlns:t3="[^"]*"//g')
					NEW_VALUE=$(xmlstarlet sel -t -c "//trans-unit[@id='${KEY}']" ${FILE} | sed -e 's/ xmlns:t3="[^"]*"//g')
					if [ "${CURRENT_VALUE}" != "${NEW_VALUE}" ]; then
						# No double quotes here around ${CURRENT_VALUE} since we don't want to keep the internal line breaks!
						# Using quotemeta make it safe for use in a regular expression
						ELEMENT=$(echo -n ${CURRENT_VALUE} | perl -pe 's|^(<trans-unit .*?>).*$|\1|' | perl -e 'print quotemeta(<STDIN>)')
						# New lines should be escaped in replacement string
						# Beware of special characters changing string to UPPER CASE and breaking the generated XLIFF:
						# see: http://perldoc.perl.org/perlre.html#Escape-sequences
						REPLACEMENT=$(echo -n "${NEW_VALUE}" | sed 's/\\/\\\\/g' | sed 's/|/\\|/g' | perl -pe 'BEGIN{undef $/;} s|\n|\\n|smg')

						perl -pe "BEGIN{undef $/;} s|${ELEMENT}.*?</trans-unit>|${REPLACEMENT}|smg" ${TARGET_NAME} > ${TARGET_NAME}.tmp
						if [ $? -ne 0 ]; then
							# THIS SHOULD NEVER HAPPEN BUT WHO KNOWS?
							echo "Real trouble happened with file ${TARGET_NAME} and key '${KEY}'" >&2
							exit 1
						fi

						# Check the correctness of the generated XLIFF
						xmlstarlet -q val ${TARGET_NAME}.tmp
						if [ $? -ne 0 ]; then
							echo "This is really bad! ${TARGET_NAME} is about to get broken!" >&2
							echo "Key: ${KEY}" >&2
							exit 2
						fi

						NUMBER_OF_KEYS_OLD=$(xmlstarlet sel -t -m "//trans-unit" -v "@id" -n ${TARGET_NAME} | wc -l)
						NUMBER_OF_KEYS_NEW=$(xmlstarlet sel -t -m "//trans-unit" -v "@id" -n ${TARGET_NAME}.tmp | wc -l)
						if [ ${NUMBER_OF_KEYS_OLD} -ne ${NUMBER_OF_KEYS_NEW} ]; then
							echo "This is really bad! ${TARGET_NAME}.tmp has now another amount of keys than ${TARGET_NAME}" >&2
							echo "Key: ${KEY}" >&2
							exit 3
						fi

						# Everything's fine: replace original file
						mv ${TARGET_NAME}.tmp ${TARGET_NAME}

						DIRTY=1
					fi
				done

				if [ $DIRTY -eq 1 ]; then
					# Reset the date of last modification
					xmlstarlet ed -u "xliff/file/@date" -v "$(date '+%Y-%m-%dT%H:%M:%SZ')" ${TARGET_NAME} > ${TARGET_NAME}.tmp
					mv ${TARGET_NAME}.tmp ${TARGET_NAME}

					# Reformat XLF with proper indent
					xmlstarlet fo -t ${TARGET_NAME} > ${TARGET_NAME}.tmp
					mv ${TARGET_NAME}.tmp ${TARGET_NAME}
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
