#!/bin/bash
export WTK_HOME=/opt/WTK2.5.2/

if [ -z "$WORKSPACE" ]; then
	if [ $# -ne 1 ]; then
    		echo "Give argument: .sh <workspace>"
    		exit 1
 	fi
	WORKSPACE=$1
fi

cd $WORKSPACE
if [ -f "${WORKSPACE}/ustadmobilemicro-build.properties" ]; then
	echo ""
else
	cp ${WORKSPACE}/ustadmobilemicro-build.default.properties ${WORKSPACE}/ustadmobilemicro-build.properties
	sed -i.backup -e "s/.*wtk.home=.*/wtk.home=\/opt\/WTK2.5.2\//" ${WORKSPACE}/ustadmobilemicro-build.properties 
	WTK_HOME_ESC=`echo ${WTK_HOME} | sed 's/\./\\\./g' | sed 's,\/,\\\/,g'`
	sed -i.backup -e "s,.*wtk\.home.*,wtk\.home=${WTK_HOME_ESC}," ${WORKSPACE}/ustadmobilemicro-build.properties
fi

NODEJS_SERVER="/opt/unittest-ustadmobilemicro/ustadmobilemicrotest-node-qunit-server.js"
RESULT_DIR="/opt/unittest-ustadmobilemicro/result"
RESULT_DIR="${WORKSPACE}/result"
mkdir ${RESULT_DIR}
ASSET_DIR="/opt/unittest-ustadmobilemicro/asset"
RASPBERRY_PI2_IP="10.8.0.6"
RASPBERRY_PI2_USER="pi"
BUILD_NAME=`grep "<project name=\"" ${WORKSPACE}/antenna-build.xml | awk -F\" '{ print $2 }'`
ASSET_PORT="6822"
CONTROL_PORT="8621"
SERVER="http://devserver2.ustadmobile.com"
TESTPOSTURL="${SERVER}:${CONTROL_PORT}"
MAX_RESULT_CHECK=200

DEVICES[0]="lg"
DEVICES[1]="nokia"

#DEVICES[0]="nokia"
#DEVICES[1]="alcatel"
#DEVICES[2]="lg"
#DEVICES[3]="samsung"

SUCCESS="false"
echo "Building.."
SUCCESS=false
#sed -i.backup -e "s/.*<device>.*/    <device>${i}<\/device>/" ${WORKSPACE}/src/com/ustadmobile/app/tests/test-settings.xml
sed -i.backup -e "s,.*<testposturl>.*,    <testposturl>${TESTPOSTURL}<\/testposturl>," ${WORKSPACE}/src/com/ustadmobile/app/tests/test-settings.xml

#Clean would remove src-preprocessed-ANTENNA and classes-ANTENNA

cd ${WORKSPACE}
/usr/bin/ant -f antenna-build.xml getlibs
/usr/bin/ant -f antenna-build.xml -lib /opt/antenna
if [ $? -eq 0 ]; then
    echo "Build success!\n"
else
    echo "Build FAILED! Please Check. Exiting.."
    exit 1;
fi

echo "Starting NodeJs Qunit Server.."

mv ${RESULT_DIR}/* ${RESULT_DIR}/OLD
rm -f ${ASSET_DIR}/*.jar
rm -f ${ASSET_DIR}/*.jad

#Remove previous results. Or archive them.

mkdir ${RESULT_DIR}/OLD
mv ${RESULT_DIR}/* ${RESULT_DIR}/OLD
#cp ${WORKSPACE}/dist-ANTENNA/*  ${ASSET_DIR}
cp ${WORKSPACE}/dist-ANTENNA/${BUILD_NAME}.jar ${ASSET_DIR}/${BUILD_NAME}.jar
cp ${WORKSPACE}/dist-ANTENNA/${BUILD_NAME}.jad ${ASSET_DIR}/${BUILD_NAME}.jad
#Start Node-Qunit-Server
nodejs ${NODEJS_SERVER} ${CONTROL_PORT} ${ASSET_PORT} ${RESULT_DIR} ${ASSET_DIR} &

SERVERPID=$! #Gets process ID
echo "Server Process id: ${SERVERPID}"
sleep 5

#ping ${TESTPOSTURL} -c 1
SERVER_BASE=`echo ${SERVER} | awk -F"http\:\/\/" '{ print $2 }'`
nc -zv ${SERVER_BASE} ${CONTROL_PORT}
if [ $? -eq 0 ];then
	echo "Server up and running. Ping a success. PID: ${SERVERPID}"
else
	echo "Could not validate NodeJS server status. Failure!. Exiting.."
	exit 1;
fi

echo "Running gammu commands to download and install in devices (connected to Raspberry pi 2 'Cloud'.."

echo "Running in parallel.."

for i in "${DEVICES[@]}"
do
    echo "Running for ${i}"
    ssh ${RASPBERRY_PI2_USER}@${RASPBERRY_PI2_IP} "python /home/pi/gammu/gammu_test.py ${i}" &
done

if [ $? -eq 0 ]; then
    echo "Raspberry pi able to be connected and run"
else
    echo "    Connection and Gammu Commands to the Raspberry Pi 2 FAILED. Please Check."
    echo "Unable to access the Raspberry ! Please check its status."
    SUCCESS="false"
    exit 1
fi

echo "Waiting for results.."

tries=1;
yep="nope"
while [[ "${yep}" == "nope" && ${tries} -lt ${MAX_RESULT_CHECK} ]]; do
    sleep 1
    yep="nope"
    for i in "${DEVICES[@]}"
    do
	yep="nope"
	if [ -f "${RESULT_DIR}/result-${i}" ];then
	    yep="yep"
	else
	    yep="nope"
	    break
	fi
	echo "Result: ${yep}"
    done	
    tries=`expr ${tries} + 1`
done
echo "All good after ${tries} tries"

tries=`expr ${tries} + 1`
if [ $tries -gt ${MAX_RESULT_CHECK} ]; then
     echo "    Timed out tries. Failure! Please check"
fi

#When all done and good . End of testing, etc
kill $SERVERPID
if [ $? -eq 0 ]; then
    echo "Killed NodeJS Server OK."
else
    echo "FAILED to Kill NodeJS server. Please Check."
fi

SUCCESS="fail"
for i in "${DEVICES[@]}"
do
    if [ -f "${RESULT_DIR}/result-${i}" ]; then
        sleep 1 #Just to make sure file is written by now
        result=`cat ${RESULT_DIR}/result-${i}`
        if [ "${result}" = "PASS" ]; then
            echo "    Test OK for Device: ${i}"
            SUCCESS="true"
            echo "Success is now: ${SUCCESS}";
        else
            echo "    Test FAIL for Device: ${i}"
            #exit 1
        fi

    else
	echo "No result for ${i}"
	SUCCESS="false"
    fi

done

if [ "${SUCCESS}" = "true" ]; then
 	echo "All devices Ran Tests OK."
	exit 0;
else
	echo "Not All devices ran successfully..Please Check"
	exit 1;
fi
