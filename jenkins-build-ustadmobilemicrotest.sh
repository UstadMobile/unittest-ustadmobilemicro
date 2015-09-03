#!/bin/bash
export WTK_HOME=/opt/WTK2.5.2/
#/usr/lib/jvm/oracle/jdk1.8
export JAVA_HOME=/usr/lib/jvm/oracle/jdk1.8

export PATH=$JAVA_HOME/bin:$PATH


echo "Workspace is: ${WORKSPACE}"
mkdir "${WORKSPACE}/test-results/"
TRF="${WORKSPACE}/test-results/results.html"
>${TRF}

TEST_RESULT_URL="https://devserver2.ustadmobile.com:8081/job/UstadMobile-J2ME-Gammu-Pi/ws/test-results/results.html"

if [ -z "$WORKSPACE" ]; then
	if [ $# -ne 1 ]; then
    		echo "Give argument: .sh <workspace>"
    		exit 1
 	fi
	WORKSPACE=$1
fi

echo "Workspace is: ${WORKSPACE}"

WORKSPACE=${WORKSPACE}/ports/j2me/

cd $WORKSPACE

echo "Checking.."
if [ -f "/var/lib/jenkins/javakey/ustadmobilemicro-build.properties" ]; then
    echo "Properties file found in javakey. Will sign this build according to the keystore"
    sed -i.backup -e "s/property\ file\=\"ustadmobilemicro\-build\.properties\"/property\ file\=\"\/var\/lib\/jenkins\/javakey\/ustadmobilemicro-build.properties\"/" ${WORKSPACE}/antenna-build.xml

elif [ -f "${WORKSPACE}/ustadmobilej2me-build.properties" ]; then
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
ASSET_DIR="${WORKSPACE}/asset"
mkdir ${ASSET_DIR}
RASPBERRY_PI2_IP="10.8.0.6"
RASPBERRY_PI2_USER="pi"
BUILD_NAME=`grep "<project name=\"" ${WORKSPACE}/antenna-build.xml | awk -F\" '{ print $2 }'`
ASSET_PORT="6822"
CONTROL_PORT="8621"
SERVER="http://devserver2.ustadmobile.com"
TESTPOSTURL="${SERVER}:${CONTROL_PORT}"
MAX_RESULT_CHECK=900
HTTPD_PORT=8055
DEVICES[0]="nokia"
DEVICES[1]="alcatel"
#DEVICES[2]="lg"

#DEVICES[0]="nokia"
#DEVICES[1]="alcatel"
#DEVICES[2]="lg"
#DEVICES[3]="samsung"

SUCCESS="false"

echo "Clearning.."
pwd
#Clean would remove src-preprocessed-ANTENNA and classes-ANTENNA
rm -rf ${WORKSPACE}/src-preprocessed-ANTENNA ${WORKSPACE}/classes-ANTENNA ${WORKSPACE}/dist-ANTENNA ${WORKSPACE}/lib
rm -rf ${WORKSPACE}../../core/classes ${WORKSPACE}../../core/dist ${WORKSPACE}../../core/lib


#New build steps
echo "Geting libraried for J2ME.."
pwd
cd ${WORKSPACE}
/usr/bin/ant -f antenna-build.xml getlibs

echo "Getting Libraried for Core.."
cd ${WORKSPACE}/../../core/
pwd
/usr/bin/ant -f antenna-build.xml getlibs


cd ${WORKSPACE}
echo "Starting Buildg.."
SUCCESS=false

cd ../../testres

IPADDR=$(/sbin/ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -n 1)

./runserver.sh ${HTTPD_PORT}
if [ $? != 0 ];then
    echo "Cannot start server. Exiting.."
    exit 1;
fi
DHDSERVERPID=$(cat DodgyHTTPD/dodgyhttpd.pid)

cd $WORKSPACE

./updatecore
if [ $? -eq 0 ]; then
    echo "Pre processing succeeded"
else
    echo "PreProcessing failed. Exiting.."
    echo "Killing server if started.."
    kill $DHDSERVERPID
    exit 1;
fi

sed s/__TESTSERVERIP__/$IPADDR/g ../../core/test/com/ustadmobile/test/core/TestConstants.java | \
    sed s/__TESTSERVERPORT__/${HTTPD_PORT}/g \
    > ./src/com/ustadmobile/test/core/TestConstants.java

TESTPOSTURL2="${IPADDR}:${HTTPD_PORT}"
echo "Test POST URL is:  ${TESTPOSTURL}"
echo "Test POST URL2 is: ${TESTPOSTURL2}"

#sed -i.backup -e "s/.*<device>.*/    <device>${i}<\/device>/" ${WORKSPACE}/src/com/ustadmobile/app/tests/test-settings.xml
sed -i.backup -e "s,.*<testposturl>.*,    <testposturl>${TESTPOSTURL}<\/testposturl>," ${WORKSPACE}/src/com/ustadmobile/test/port/j2me/test-settings.xml


echo "Building J2ME.."
cd ${WORKSPACE}
/usr/bin/ant -f antenna-build.xml -lib /opt/antenna sign

if [ $? -eq 0 ]; then
    echo "Build success!\n"
else
    echo "Build FAILED! Please Check. Exiting.."
    echo "Killing server if started.."
    kill $DHDSERVERPID
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
        echo "Killing Server.."
    	kill $DHDSERVERPID
	echo "Killing nodejs if running.."
	kill $SERVERPID
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
    echo "Closing server.."
    kill $DHDSERVERPID
    echo "Killing nodejs server.."
    kill $SERVERPID
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
	#echo "Result: ${yep}"
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

echo "End of test. Killing Server.."
kill ${DHDSERVERPID}

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
for file in ${RESULT_DIR}/node-qunit-testresults*
        do
            echo "${file}:" >> ${TRF}
	    echo "" >> ${TRF}
            cat $file >> ${TRF}
	    echo "" >> ${TRF}
	    echo "" >> ${TRF}
        done

#https://devserver2.ustadmobile.com:8081/job/UstadMobile-J2ME-Gammu-Pi/ws/test-results/results.html

if [ "${SUCCESS}" = "true" ]; then
 	echo "All devices Ran Tests OK."
	echo "The test results are here: ${TEST_RESULT_URL}"
	exit 0;
else
	echo "Not All devices ran successfully..Please Check"
	echo "The test results are here: ${TEST_RESULT_URL}"
	exit 1;
fi
