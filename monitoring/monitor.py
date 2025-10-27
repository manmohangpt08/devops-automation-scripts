#!/usr/bin/python
import sys
import boto3
import requests
from configparser import ConfigParser
import os
import json
import logging

parser = ConfigParser()
parser.read('config.ini')


logging.basicConfig(filename=parser.get('system', 'monitoring_log_file_path'),format='%(asctime)s %(levelname)s %(message)s',filemode='a')
logger = logging.getLogger()
logger.setLevel(logging.WARNING)
instance_id="development-instance"
region1 = parser.get('aws','region_name')

environment = parser.get('system', 'environment')
instance_name = parser.get('system', 'instance_name')
sns = boto3.client("sns", region_name=region1)
topic = parser.get('aws','sns_topic')
topic2 = parser.get('aws','sns_topic2')
profile = parser.get('aws','profile')

def isResponseValid(appName, url_or_command, type, response_type, validResponse=None):
    if type == "url":
        try:
            response = requests.get(url_or_command, timeout=1).text
        except requests.exceptions.RequestException as e:
            response = "none"
        if response_type == "empty" and response == "none"  or response_type == "value" and response.strip() != validResponse:
            previous_status=parser.get(appName,'current_status')
            current_status="FAIL"
            updatestatus(appName,previous_status,current_status)
            logger.warning("Unable to get status of " + appName + " on " + instance_name)
            message = "Unable to get status of " + appName + " on " + instance_name
            subject = environment + " Healthcheck alert"
            sendAlert(appName,topic, message, subject)
        else:
            previous_status=parser.get(appName,'current_status')
            current_status="PASS"
            updatestatus(appName,previous_status,current_status)
            logger.info(appName + " is now working fine on " + instance_name)
            message = appName + " is now working fine on " + instance_name
            subject = environment + "  Healthcheck alert"
            sendAlert(appName,topic, message, subject)
    elif type == "command": 
        response = os.popen(url_or_command).read().strip('\n')
        if (response_type == "empty" and (response == "" or response == "0"))  or (response_type == "value" and response.strip() != validResponse):
            previous_status=parser.get(appName,'current_status')
            current_status="FAIL"
            updatestatus(appName,previous_status,current_status)
            logger.warning("Unable to get status of " + appName + " on " + instance_name)
            message = "Unable to get status of " + appName + " on " + instance_name
            subject = environment + " Healthcheck alert"
            if (type == "command" and response_type == "empty"):
                sendAlert2(appName,topic2, message, subject)
            else:
                sendAlert(appName,topic, message, subject)
        else:
            previous_status=parser.get(appName,'current_status')
            current_status="PASS"
            updatestatus(appName,previous_status,current_status)
            logger.info(appName + " is now working fine on " + instance_name)
            message = appName + " is now working fine on " + instance_name
            subject = environment + " Healthcheck alert"
            if (type == "command" and response_type == "empty"):
                sendAlert2(appName,topic2, message, subject)
            else:
                sendAlert(appName,topic, message, subject)

def updatestatus(appname, previous_status, current_status):
    status = parser[appname]
    status["previous_status"] = previous_status
    status["current_status"] = current_status
    try:
        with open('/home/opc/monitoring/config.ini', 'w') as statusfile:
            parser.write(statusfile)
            statusfile.close()
    except Exception as e:
        logger.warning("Failed to Write Status of " + appname + " in Config File")
        logger.exception(e)
        
def sendAlert(appname,topic,message,subject):
    Previous_Status=parser.get(appname,'previous_status')
    Current_Status=parser.get(appname, 'current_status')
    if Previous_Status != Current_Status:
        logger.error("Previous status is not equal to Current Status --> Check If there is loop Emails")
        logger.error(str(appname) + "Previous Status = " + str(Previous_Status) + " and " + "Current Status = " + str(Current_Status))
        sns_client = boto3.Session(profile_name=profile).client('sns', region_name=region1)
        sns_client.publish(TopicArn=topic, Message=message, Subject=subject)
        logger.error("TopicArn= " + topic + "  Message= " + message + "  subject= " + subject)

def sendAlert2(appname,topic2,message,subject):
    Previous_Status=parser.get(appname,'previous_status')
    Current_Status=parser.get(appname, 'current_status')
    if Previous_Status != Current_Status:
        logger.error("Previous status is not equal to Current Status --> Check If there is loop Emails")
        logger.error(str(appname) + "Previous Status = " + str(Previous_Status) + " and " + "Current Status = " + str(Current_Status))
        sns_client = boto3.Session(profile_name=profile).client('sns', region_name=region1)
        sns_client.publish(TopicArn=topic2, Message=message, Subject=subject)
        logger.error("TopicArn= " + topic2 + "  Message= " + message + "  subject= " + subject)

def process(processname):
    cpuutil=os.popen("ps aux | grep %s | grep -v grep | awk  '{print $3}'| head -n1" % processname).read().strip('\n')
    memutil=os.popen("ps aux | grep %s | grep -v grep | awk  '{print $4}'| head -n1" % processname).read().strip('\n')
    pid=os.popen("ps aux | grep %s | grep -v grep | awk  '{print $2}'| head -n1" % processname).read().strip('\n')
    if pid != "":
        variable=1
    else:
        variable=0
    if cpuutil != "":
        cpu=float(cpuutil)
    else:
        cpu=0
    
    if memutil != "":
        mem=float(memutil)
    else:
        mem=0
    
    return cpu,mem,variable

client=boto3.client('cloudwatch',region_name=region1)
def put_data(metricname,value,namespace):
    client.put_metric_data(
       MetricData=[
           {
               'MetricName': metricname,
               'Dimensions':[
                   {
                       'Name' : 'InstanceId',
                       'Value' : instance_id
                   },
               ],
               'Unit' : 'None',
               'Value' : value
           },
       ],
       Namespace = namespace
    )
    print("Metric Name = " + metricname + " namespace = " + namespace)
    logger.info("Metric Name = " + metricname + " namespace = " + namespace)


def monitor_apache():
    if parser.get('apache','enabled') == "true":
        cpu,memory,apache = process("httpd")
        metricname=parser.get('apache','metricname')
        namespace=parser.get('apache','namespace')
        pingURL=parser.get('apache','pingURL')
        valid_response=parser.get('apache', 'valid_response')
        if apache != 0:
            isResponseValid(appName="apache", url_or_command=pingURL, validResponse=valid_response, type="url", response_type="value")
        else:
            previous_status=parser.get('apache', 'current_status')
            current_status="FAIL"
            updatestatus("apache", previous_status, current_status)
            logger.error("Apache Webserver is down on " + instance_name)
            message = "Apache Webserver is down on " + instance_name
            subject = environment + " Healthcheck alert"
            sendAlert("apache",topic, message, subject)
        put_data(metricname,apache,namespace)
        put_data((metricname + "-cpu"),cpu,namespace)
        put_data((metricname + "-mem"),memory,namespace)

def monitor_tomcat():
    if parser.get('tomcat','enabled') == "true":
        cpu,memory,tomcat = process("tomcat")
        metricname=parser.get('tomcat','metricname')
        namespace=parser.get('tomcat','namespace')
        pingURL=parser.get('tomcat','pingURL')
        valid_response=parser.get('tomcat', 'valid_response')
        if tomcat != 0:
            isResponseValid(appName="tomcat", url_or_command=pingURL, validResponse=valid_response, type="url", response_type="value")
        else:
            previous_status=parser.get('tomcat', 'current_status')
            current_status="FAIL"
            updatestatus("tomcat", previous_status, current_status)
            logger.error("Tomcat Application is down on " + instance_name)
            message = "Tomcat Application is down on " + instance_name
            subject = environment + " Healthcheck alert"
            sendAlert("tomcat",topic, message, subject)
        put_data(metricname,tomcat,namespace)
        put_data((metricname + "-cpu"),cpu,namespace)
        put_data((metricname + "-mem"),memory,namespace)

def monitor_kafka():
    if parser.get('kafka','enabled') == "true":
        cpu,memory,kafka = process("kafkaServer")
        metricname=parser.get('kafka','metricname')
        namespace=parser.get('kafka','namespace')
        if kafka == 0:
            previous_status=parser.get('kafka', 'current_status')
            current_status="FAIL"
            updatestatus("kafka", previous_status, current_status)
            logger.error("Kafka Application is Down on " + instance_name)
            message = "Kafka Application is Down on " + instance_name
            subject = environment + " Healthcheck Alert"
            sendAlert("kafka",topic, message, subject)
        else:
            previous_status=parser.get('kafka', 'current_status')
            current_status="PASS"
            updatestatus("kafka", previous_status, current_status)
            message = "Kafka Application is now working fine on " + instance_name
            subject = environment + " Healthcheck Alert"
            sendAlert("kafka",topic, message, subject)
        put_data(metricname,kafka,namespace)
        put_data((metricname + "-cpu"),cpu,namespace)
        put_data((metricname + "-mem"),memory,namespace)

def monitor_zookeeper():
    if parser.get('zookeeper','enabled') == "true":
        cpu,memory,zookeeper = process("zookeeper.server")
        metricname=parser.get('zookeeper','metricname')
        namespace=parser.get('zookeeper','namespace')
        command=parser.get('zookeeper','command')
        valid_response=parser.get('zookeeper', 'valid_response')
        if zookeeper != 0:
            isResponseValid(appName="zookeeper", url_or_command=command, validResponse=valid_response, type="command", response_type="value")
        else:
            previous_status=parser.get('zookeeper', 'current_status')
            current_status="FAIL"
            updatestatus("zookeeper", previous_status, current_status)
            logger.error("Zookeeper Application is down on " + instance_name)
            message = "Unable to get status of Zookeeper on " + instance_name
            subject = environment + " Healthcheck alert"
            sendAlert("zookeeper",topic, message, subject)
        put_data(metricname,zookeeper,namespace)
        put_data((metricname + "-cpu"),cpu,namespace)
        put_data((metricname + "-mem"),memory,namespace)

def monitor_realtime():
    if parser.get('druid_realtime','enabled') == "true":
        cpu,memory,realtime = process("realtime")
        metricname=parser.get('druid_realtime','metricname')
        namespace=parser.get('druid_realtime','namespace')
        pingURL=parser.get('druid_realtime','pingURL')
        if realtime != 0:
            isResponseValid(appName="druid_realtime", url_or_command=pingURL, type="url", response_type="empty")
        else:
            previous_status=parser.get('druid_realtime', 'current_status')
            current_status="FAIL"
            updatestatus("druid_realtime", previous_status, current_status)
            logger.error("Druid Realtime Node is down on " + instance_name)
            message = "Druid Realtime Node is down on " + instance_name
            subject = environment + " Healthcheck alert"
            sendAlert("druid_realtime",topic, message, subject)
        put_data(metricname,realtime,namespace)
        put_data((metricname + "-cpu"),cpu,namespace)
        put_data((metricname + "-mem"),memory,namespace)

def monitor_broker():
    if parser.get('druid_broker','enabled') == "true":
        cpu,memory,broker = process("broker")
        metricname=parser.get('druid_broker','metricname')
        namespace=parser.get('druid_broker','namespace')
        pingURL=parser.get('druid_broker','pingURL')
        if broker != 0:
            isResponseValid(appName="druid_broker", url_or_command=pingURL, type="url", response_type="empty")
        else:
            previous_status=parser.get('druid_broker', 'current_status')
            current_status="FAIL"
            updatestatus("druid_broker", previous_status, current_status)
            logger.error("Druid Broker Node is down on " + instance_name)
            message = "Druid Broker Node is down on " + instance_name
            subject = environment + " Healthcheck alert"
            sendAlert("druid_broker",topic, message, subject)
        put_data(metricname,broker,namespace)
        put_data((metricname + "-cpu"),cpu,namespace)
        put_data((metricname + "-mem"),memory,namespace)

def monitor_coordinator():
    if parser.get('druid_coordinator','enabled') == "true":
        cpu,memory,coordinator = process("coordinator")
        metricname=parser.get('druid_coordinator','metricname')
        namespace=parser.get('druid_coordinator','namespace')
        pingURL=parser.get('druid_coordinator','pingURL')
        if coordinator != 0:
            isResponseValid(appName="druid_coordinator", url_or_command=pingURL, type="url", response_type="empty")
        else:
            previous_status=parser.get('druid_coordinator', 'current_status')
            current_status="FAIL"
            updatestatus("druid_coordinator", previous_status, current_status)
            logger.error("Druid Coordinator Node is down on " + instance_name)
            message = "Druid Coordinator Node is down on " + instance_name
            subject = environment + " Healthcheck alert"
            sendAlert("druid_coordinator",topic, message, subject)
        put_data(metricname,coordinator,namespace)
        put_data((metricname + "-cpu"),cpu,namespace)
        put_data((metricname + "-mem"),memory,namespace)

def monitor_historical():
    if parser.get('druid_historical','enabled') == "true":
        cpu,memory,historical = process("historical")
        metricname=parser.get('druid_historical','metricname')
        namespace=parser.get('druid_historical','namespace')
        pingURL=parser.get('druid_historical','pingURL')
        if historical != 0:
            isResponseValid(appName="druid_historical", url_or_command=pingURL, type="url", response_type="empty")
        else:
            previous_status=parser.get('druid_historical', 'current_status')
            current_status="FAIL"
            updatestatus("druid_historical", previous_status, current_status)
            logger.error("Druid Historical Node is down on " + instance_name)
            message = "Druid Historical Node is down on " + instance_name
            subject = environment + " Healthcheck alert"
            sendAlert("druid_historical",topic, message, subject)
        put_data(metricname,historical,namespace)
        put_data((metricname + "-cpu"),cpu,namespace)
        put_data((metricname + "-mem"),memory,namespace)

def monitor_elasticsearch():
    if parser.get('elasticsearch','enabled') == "true":
        cpu,memory,elasticsearch = process("elasticsearch.pid")
        metricname=parser.get('elasticsearch','metricname')
        namespace=parser.get('elasticsearch','namespace')
        pingURL=parser.get('elasticsearch','pingURL')
        if elasticsearch != 0:
            isResponseValid(appName="elasticsearch", url_or_command=pingURL, type="url", response_type="empty")
        else:
            previous_status=parser.get('elasticsearch', 'current_status')
            current_status="FAIL"
            updatestatus("elasticsearch", previous_status, current_status)
            logger.error("Elasticsearch is down on " + instance_name)
            message = "Elasticsearch is down on " + instance_name
            subject = environment + " Healthcheck alert"
            sendAlert("elasticsearch",topic, message, subject)
        put_data(metricname,elasticsearch,namespace)
        put_data((metricname + "-cpu"),cpu,namespace)
        put_data((metricname + "-mem"),memory,namespace)

def monitor_mysql():
    if parser.get('mysql','enabled') == "true":
        cpu,memory,mysql = process("mysqld")
        metricname=parser.get('mysql','metricname')
        namespace=parser.get('mysql','namespace')
        if mysql == 0:
            previous_status=parser.get('mysql', 'current_status')
            current_status="FAIL"
            updatestatus("mysql", previous_status, current_status)
            logger.error("MySQL database application is down on " + instance_name)
            message = "MySQL database application is down on " + instance_name
            subject = environment + " Healthcheck alert"
            sendAlert("mysql",topic, message, subject)
        else:
            previous_status=parser.get('mysql', 'current_status')
            current_status="PASS"
            updatestatus("mysql", previous_status, current_status)
            message = "MySQL database application is now working fine on " + instance_name
            subject = environment + " Healthcheck alert"
            sendAlert("mysql",topic, message, subject)
        put_data(metricname,mysql,namespace)
        put_data((metricname + "-cpu"),cpu,namespace)
        put_data((metricname + "-mem"),memory,namespace)

def monitor_kafka_zk_conn():
    if parser.get('zookeeper_kafka_connection','enabled') == "true":
        command=parser.get('zookeeper_kafka_connection', 'command')
        isResponseValid(appName="zookeeper_kafka_connection", url_or_command=command, type="command", response_type="empty")

def monitor_realtime_zk_conn():
    if parser.get('realtime_zookeeper_connection','enabled') == "true":
        command=parser.get('realtime_zookeeper_connection', 'command')
        isResponseValid(appName="realtime_zookeeper_connection", url_or_command=command, type="command", response_type="empty")

def monitor_broker_zk_conn():
    if parser.get('broker_zookeeper_connection','enabled') == "true":
        command=parser.get('broker_zookeeper_connection', 'command')
        isResponseValid(appName="broker_zookeeper_connection", url_or_command=command, type="command", response_type="empty")

def monitor_historical_zk_conn():
    if parser.get('historical_zookeeper_connection','enabled') == "true":
        command=parser.get('historical_zookeeper_connection', 'command')
        isResponseValid(appName="historical_zookeeper_connection", url_or_command=command, type="command", response_type="empty")

def monitor_coordinator_zk_conn():
    if parser.get('coordinator_zookeeper_connection','enabled') == "true":
        command=parser.get('coordinator_zookeeper_connection', 'command')
        isResponseValid(appName="coordinator_zookeeper_connection", url_or_command=command, type="command", response_type="empty")

def changeDate(file_path):
    current_date = os.popen("date +%Y-%m-%d").read().strip('\n')
    with open(file_path, 'r') as file:
        file_content = file.read()
    if current_date not in file_content:
        backup_file_path = file_path + "_bak"
        os.system("cp {} {}".format(backup_file_path, file_path))
        os.system("sed -i 's/DATE/{}/g' {}".format(current_date, file_path))


monitor_kafka()
monitor_zookeeper()
monitor_realtime()
monitor_broker()
monitor_coordinator()
monitor_historical()
monitor_apache()
monitor_elasticsearch()
monitor_mysql()
monitor_kafka_zk_conn()
monitor_realtime_zk_conn()
monitor_broker_zk_conn()
monitor_historical_zk_conn()
monitor_coordinator_zk_conn()