#!/usr/bin/env bash

source ../TYPO3.conf

echo "[INFO]    Creating Pootle project files into ${TARGET}"
rm -rf ${TARGET}
mkdir -p ${TARGET}

echo "[INFO]    Creating archive of TYPO3 CMS localization files on server"
ssh root@translation.typo3.org "rm -rf /tmp/pootle-typo3; \
	mkdir /tmp/pootle-typo3; \
	cp -r /var/www/vhosts/pootle.typo3.org/pootle/po/TYPO3.TYPO3.core.* /tmp/pootle-typo3; \
	find /tmp/pootle-typo3 -type d -name .translation_index -exec rm -rf {} \; ; \
	rm -f /tmp/pootle-typo3.tar.gz; \
	tar -C /tmp/pootle-typo3 -czf /tmp/pootle-typo3.tar.gz ." >/dev/null 2>&1

echo "[INFO]    Fetching generated archive"
scp root@translation.typo3.org:/tmp/pootle-typo3.tar.gz ${TARGET}
ssh root@translation.typo3.org "rm -f /tmp/pootle-typo3.tar.gz"

pushd ${TARGET} >/dev/null

echo "[INFO]    Unarchaving localization files"
tar xzf pootle-typo3.tar.gz
rm pootle-typo3.tar.gz
echo "[INFO]    Initializing Git repository"
git init >/dev/null 2>&1
echo ".typo3/" > .gitignore
git add . >/dev/null 2>&1
git commit -m "[TASK] Import from Pootle 1.9.0" >/dev/null 2>&1

PROJECTS=$(find . -type d -maxdepth 1 | cut -b3- | grep -v .git)
for PROJECT in ${PROJECTS}; do
	pushd ${PROJECT} >/dev/null

	echo "[INFO]    Migrating ${PROJECT}"
	LANGUAGES=$(find . -type d -maxdepth 1 | cut -b3-)
	for LANGUAGE in ${LANGUAGES}; do
		pushd ${LANGUAGE} >/dev/null
		rm -rf .converted
		mkdir .converted

		FILES=$(find . -name \*.xlf)
		for FILE in ${FILES}; do
			T3ID=$(xmlstarlet sel -t -m "//xliff/file" -v "@t3:id" ${FILE} 2>/dev/null)
			if [ -z "${T3ID}" ]; then
				# Legacy file: keep it as-is
				continue
			fi
			TARGET_NAME=.converted/locallang.${T3ID}.xlf
			if [ -f ${TARGET_NAME} ]; then
				echo "[ERROR]   OOOPS! Duplicate T3ID ${T3ID} with $FILE" >&2
				exit 1
			fi
			mv $FILE ${TARGET_NAME}
		done

		mv .converted/*.xlf . >/dev/null 2>&1
		rmdir .converted

		# Remove empty directories
		find . -type d | sort -r | xargs rmdir >/dev/null 2>&1
		                        
		popd >/dev/null
	done

	git add . >/dev/null 2>&1
	git commit -m "[TASK] Migrate ${PROJECT}" >/dev/null 2>&1

	popd >/dev/null
done

popd >/dev/null
