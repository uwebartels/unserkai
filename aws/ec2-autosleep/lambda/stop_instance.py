import logging
import os

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ec2 = boto3.client("ec2")
INSTANCE_ID = os.environ["EC2_INSTANCE_ID"]


def lambda_handler(event, context):
    logger.info("CloudWatch alarm invoked stop function: %s", event)

    try:
        response = ec2.describe_instances(InstanceIds=[INSTANCE_ID])
        instances = [
            instance
            for reservation in response.get("Reservations", [])
            for instance in reservation.get("Instances", [])
        ]

        if not instances:
            logger.error("Instance %s was not found", INSTANCE_ID)
            return {"status": "not_found", "instance_id": INSTANCE_ID}

        state = instances[0]["State"]["Name"]
        logger.info("Current state of %s: %s", INSTANCE_ID, state)

        if state not in ("running", "pending"):
            logger.info("Instance is not running or pending; no stop needed")
            return {"status": "not_running", "instance_id": INSTANCE_ID, "state": state}

        result = ec2.stop_instances(InstanceIds=[INSTANCE_ID])
        logger.info("StopInstances response: %s", result)
        return {"status": "stop_requested", "instance_id": INSTANCE_ID}

    except ClientError:
        logger.exception("Failed to stop EC2 instance %s", INSTANCE_ID)
        raise
