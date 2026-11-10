import logging
import os
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

cloudwatch = boto3.client("cloudwatch")
ALARM_NAME = os.environ["ALARM_NAME"]
METRIC_NAMESPACE = "Custom/EC2AutoSleep"
METRIC_NAME = "Tcp8080AcceptedFlowRecords"


def lambda_handler(event, context):
    logger.info("EC2 running event received: %s", event)

    try:
        # Reset the alarm from ALARM to OK after an EC2 start.
        cloudwatch.set_alarm_state(
            AlarmName=ALARM_NAME,
            StateValue="OK",
            StateReason="EC2 entered running state; a fresh inactivity window starts now.",
        )

        # Publish one non-breaching datapoint. With 30 of 30 datapoints
        # required to breach, this heartbeat prevents the old idle window
        # from immediately stopping a freshly started instance.
        cloudwatch.put_metric_data(
            Namespace=METRIC_NAMESPACE,
            MetricData=[
                {
                    "MetricName": METRIC_NAME,
                    "Timestamp": datetime.now(timezone.utc),
                    "Value": 1,
                    "Unit": "Count",
                }
            ],
        )

        logger.info("Alarm reset and startup heartbeat published for %s", ALARM_NAME)
        return {"status": "alarm_reset", "alarm_name": ALARM_NAME}

    except ClientError:
        logger.exception("Failed to reset CloudWatch alarm %s", ALARM_NAME)
        raise
