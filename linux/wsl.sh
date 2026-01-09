#!/usr/bin/env bash
release-ram() { echo 1 | sudo tee /proc/sys/vm/drop_caches; }

if [ -z ${USERPROFILE+x} ]; then
	echoGrey "Need to share WSL variable \$USERPROFILE!"
	echoGrey "Ignore this error if you're using \"su -\". Next time, use \"su root\"."
fi
