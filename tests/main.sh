#!/bin/sh
# SPDX-License-Identifier: LGPL-2.1+

set -eu
[ -n "${DEBUG:-}" ] && set -x

[ $(id -u) -eq 0 ]

# Run lxcfs testsuite
export LXCFSDIR=$(mktemp -d)
pidfile=$(mktemp)

cmdline=$(realpath $0)
dirname=$(dirname ${cmdline})
topdir=$(dirname ${dirname})

p=-1
FAILED=1
cleanup() {
	echo "=> Cleaning up"
	set +e
	if [ $p -ne -1 ]; then
		kill -9 $p
	fi
	if [ ${LXCFSDIR} != "/var/lib/lxcfs" ]; then
		umount -l ${LXCFSDIR}
		rmdir ${LXCFSDIR}
	fi
	rm -f ${pidfile}
	if [ ${FAILED} -eq 1 ]; then
		echo "=> FAILED at $TESTCASE"
		exit 1
	fi
	echo "=> PASSED"
	exit 0
}

TESTCASE="setup"
lxcfs=${topdir}/src/lxcfs

if [ -x ${lxcfs} ]; then
	export LD_LIBRARY_PATH="${topdir}/src/.libs/"
	echo "=> Spawning ${lxcfs} ${LXCFSDIR}"
	${lxcfs} -p ${pidfile} ${LXCFSDIR} &
	p=$!
else
	pidof lxcfs
	echo "=> Re-using host lxcfs"
	rmdir $LXCFSDIR
	export LXCFSDIR=/var/lib/lxcfs
fi

trap cleanup EXIT HUP INT TERM

count=1
while ! mountpoint -q $LXCFSDIR; do
	sleep 1s
	if [ $count -gt 5 ]; then
		echo "lxcfs failed to start"
		false
	fi
	count=$((count+1))
done

RUNTEST() {
	echo ""
	echo "=> Running ${TESTCASE}"

	if [ "${UNSHARE:-1}" != "0" ]; then
		unshare -fmp --mount-proc $*
	else
		$*
	fi
}

TESTCASE="test_proc"
RUNTEST ${dirname}/test_proc
TESTCASE="test_cgroup"
RUNTEST ${dirname}/test_cgroup
TESTCASE="test_read_proc.sh"
RUNTEST ${dirname}/test_read_proc.sh
TESTCASE="cpusetrange"
RUNTEST ${dirname}/cpusetrange
TESTCASE="meminfo hierarchy"
RUNTEST ${dirname}/test_meminfo_hierarchy.sh
TESTCASE="liblxcfs reloading"
UNSHARE=0 RUNTEST ${dirname}/test_reload.sh

# Check for any defunct processes - children we didn't reap
n=`ps -ef | grep lxcfs | grep defunct | wc -l`
[ $n = 0 ]

FAILED=0
