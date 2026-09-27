import os
import boto3

ECS = boto3.client("ecs")
CLUSTER = os.environ["ECS_CLUSTER"]
SERVICE = os.environ["ECS_SERVICE"]


def handler(event, context):
    """Force a rolling deployment so ECS re-resolves Secrets Manager values."""
    response = ECS.update_service(
        cluster=CLUSTER,
        service=SERVICE,
        forceNewDeployment=True,
    )
    return {
        "serviceArn": response["service"]["serviceArn"],
        "deploymentTriggered": True,
    }
