#!/usr/bin/env bash

source TYPO3.conf

rm -rf ${TARGET}
mkdir -p ${TARGET}

ssh root@translation.typo3.org "rm -rf /tmp/pootle-typo3; \
	mkdir /tmp/pootle-typo3; \
	cp -r /var/www/vhosts/pootle.typo3.org/pootle/po/TYPO3.TYPO3.core.* /tmp/pootle-typo3; \
	find /tmp/pootle-typo3 -type d -name .translation_index -exec rm -rf {} \; ; \
	rm -f /tmp/pootle-typo3.tar.gz; \
	tar -C /tmp/pootle-typo3 -czf /tmp/pootle-typo3.tar.gz ."

scp root@translation.typo3.org:/tmp/pootle-typo3.tar.gz ${TARGET}
ssh root@translation.typo3.org "rm -f /tmp/pootle-typo3.tar.gz"

pushd ${TARGET} >/dev/null

tar xzvf pootle-typo3.tar.gz
rm pootle-typo3.tar.gz

popd >/dev/null
