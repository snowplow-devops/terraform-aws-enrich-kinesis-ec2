locals {
  module_name    = "enrich-kinesis-ec2"
  module_version = "0.6.1"

  app_name    = "enrich-kinesis"
  app_version = var.app_version

  local_tags = {
    Name           = var.name
    app_name       = local.app_name
    app_version    = local.app_version
    module_name    = local.module_name
    module_version = local.module_version
  }

  tags = merge(
    var.tags,
    local.local_tags
  )

  cloudwatch_log_group_name = "/aws/ec2/${var.name}"
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  is_aws_global = replace(data.aws_region.current.name, "cn-", "") == data.aws_region.current.name
  iam_partition = local.is_aws_global ? "aws" : "aws-cn"

  is_private_ecr_registry = var.private_ecr_registry != ""
  private_ecr_registry_statement = [{
    Action = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer"
    ]
    Effect = "Allow"
    Resource = [
      "*"
    ]
  }]
  private_ecr_registry_statement_final = local.is_private_ecr_registry ? local.private_ecr_registry_statement : []
}

module "telemetry" {
  source  = "snowplow-devops/telemetry/snowplow"
  version = "0.5.0"

  count = var.telemetry_enabled ? 1 : 0

  user_provided_id = var.user_provided_id
  cloud            = "AWS"
  region           = data.aws_region.current.name
  app_name         = local.app_name
  app_version      = local.app_version
  module_name      = local.module_name
  module_version   = local.module_version
}

# --- DynamoDB: KCL Table

resource "aws_dynamodb_table" "kcl" {
  name           = var.name
  hash_key       = "leaseKey"
  write_capacity = 1
  read_capacity  = 1

  attribute {
    name = "leaseKey"
    type = "S"
  }

  lifecycle {
    ignore_changes = [write_capacity, read_capacity]
  }

  tags = local.tags
}

module "kcl_autoscaling" {
  source  = "snowplow-devops/dynamodb-autoscaling/aws"
  version = "0.2.0"

  table_name = aws_dynamodb_table.kcl.id

  read_min_capacity  = var.kcl_read_min_capacity
  read_max_capacity  = var.kcl_read_max_capacity
  write_min_capacity = var.kcl_write_min_capacity
  write_max_capacity = var.kcl_write_max_capacity
}

# --- DynamoDB: Configuration Table

resource "aws_dynamodb_table" "config" {
  name           = "${var.name}-config"
  hash_key       = "id"
  write_capacity = 1
  read_capacity  = 1

  attribute {
    name = "id"
    type = "S"
  }

  lifecycle {
    ignore_changes = [write_capacity, read_capacity]
  }

  tags = local.tags
}

module "config_autoscaling" {
  source  = "snowplow-devops/dynamodb-autoscaling/aws"
  version = "0.2.0"

  table_name = aws_dynamodb_table.config.id
}

# --- CloudWatch: Logging

resource "aws_cloudwatch_log_group" "log_group" {
  count = var.cloudwatch_logs_enabled ? 1 : 0

  name              = local.cloudwatch_log_group_name
  retention_in_days = var.cloudwatch_logs_retention_days

  tags = local.tags
}

# --- IAM: Roles & Permissions

locals {
  custom_s3_hosted_assets_bucket_statement = [{
    Action = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:ListBucket"
    ]
    Effect = "Allow"
    Resource = [
      "arn:${local.iam_partition}:s3:::${var.custom_s3_hosted_assets_bucket_name}",
      "arn:${local.iam_partition}:s3:::${var.custom_s3_hosted_assets_bucket_name}/*"
    ]
  }]

  custom_s3_hosted_assets_bucket_statement_final = var.custom_s3_hosted_assets_bucket_name != "" ? local.custom_s3_hosted_assets_bucket_statement : []
}

resource "aws_iam_role" "iam_role" {
  name        = var.name
  description = "Allows the nodes to access required services"
  tags        = local.tags

  assume_role_policy = <<EOF
{
  "Version" : "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": [ "ec2.amazonaws.com" ]},
      "Action": [ "sts:AssumeRole" ]
    }
  ]
}
EOF

  permissions_boundary = var.iam_permissions_boundary
}

resource "aws_iam_policy" "iam_policy" {
  name = var.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = concat(
      local.private_ecr_registry_statement_final,
      local.custom_s3_hosted_assets_bucket_statement_final,
      [
        {
          Effect = "Allow",
          Action = [
            "kinesis:DescribeStream",
            "kinesis:DescribeStreamSummary",
            "kinesis:List*"
          ],
          Resource = [
            "arn:${local.iam_partition}:kinesis:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:stream/${var.in_stream_name}",
            "arn:${local.iam_partition}:kinesis:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:stream/${var.enriched_stream_name}",
            "arn:${local.iam_partition}:kinesis:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:stream/${var.bad_stream_name}"
          ]
        },
        {
          Effect = "Allow",
          Action = [
            "kinesis:Get*"
          ],
          Resource = [
            "arn:${local.iam_partition}:kinesis:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:stream/${var.in_stream_name}"
          ]
        },
        {
          Effect = "Allow",
          Action = [
            "kinesis:Put*"
          ],
          Resource = [
            "arn:${local.iam_partition}:kinesis:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:stream/${var.enriched_stream_name}",
            "arn:${local.iam_partition}:kinesis:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:stream/${var.bad_stream_name}"
          ]
        },
        {
          Effect = "Allow",
          Action = [
            "dynamodb:BatchWriteItem",
            "dynamodb:PutItem",
            "dynamodb:DescribeTable",
            "dynamodb:DeleteItem",
            "dynamodb:GetItem",
            "dynamodb:Scan",
            "dynamodb:UpdateItem"
          ],
          Resource = [
            "${aws_dynamodb_table.kcl.arn}"
          ]
        },
        {
          Effect = "Allow",
          Action = [
            "dynamodb:DescribeTable",
            "dynamodb:GetItem",
            "dynamodb:Scan"
          ],
          Resource = [
            "${aws_dynamodb_table.config.arn}"
          ]
        },
        {
          Effect = "Allow",
          Action = [
            "logs:PutLogEvents",
            "logs:CreateLogStream",
            "logs:DescribeLogStreams"
          ],
          Resource = [
            "arn:${local.iam_partition}:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:${local.cloudwatch_log_group_name}:*"
          ]
        },
        {
          Effect = "Allow",
          Action = [
            "s3:GetObject",
            "s3:GetObjectVersion",
            "s3:ListBucket"
          ],
          Resource = [
            "arn:${local.iam_partition}:s3:::snowplow-hosted-assets",
            "arn:${local.iam_partition}:s3:::snowplow-hosted-assets/*",
            "arn:${local.iam_partition}:s3:::snowplow-hosted-assets-us-east-1",
            "arn:${local.iam_partition}:s3:::snowplow-hosted-assets-us-east-1/*",
            "arn:${local.iam_partition}:s3:::snowplow-hosted-assets-us-west-1",
            "arn:${local.iam_partition}:s3:::snowplow-hosted-assets-us-west-1/*",
            "arn:${local.iam_partition}:s3:::snowplow-hosted-assets-us-west-2",
            "arn:${local.iam_partition}:s3:::snowplow-hosted-assets-us-west-2/*",
            "arn:${local.iam_partition}:s3:::snowplow-hosted-assets-sa-east-1",
            "arn:${local.iam_partition}:s3:::snowplow-hosted-assets-sa-east-1/*",
            "arn:${local.iam_partition}:s3:::snowplow-hosted-assets-eu-central-1",
            "arn:${local.iam_partition}:s3:::snowplow-hosted-assets-eu-central-1/*",
            "arn:${local.iam_partition}:s3:::snowplow-hosted-assets-ap-southeast-1",
            "arn:${local.iam_partition}:s3:::snowplow-hosted-assets-ap-southeast-1/*",
            "arn:${local.iam_partition}:s3:::snowplow-hosted-assets-ap-southeast-2",
            "arn:${local.iam_partition}:s3:::snowplow-hosted-assets-ap-southeast-2/*",
            "arn:${local.iam_partition}:s3:::snowplow-hosted-assets-ap-northeast-1",
            "arn:${local.iam_partition}:s3:::snowplow-hosted-assets-ap-northeast-1/*",
            "arn:${local.iam_partition}:s3:::snowplow-hosted-assets-ap-south-1",
            "arn:${local.iam_partition}:s3:::snowplow-hosted-assets-ap-south-1/*",
            "arn:${local.iam_partition}:s3:::snowplow-hosted-assets-us-east-2",
            "arn:${local.iam_partition}:s3:::snowplow-hosted-assets-us-east-2/*",
            "arn:${local.iam_partition}:s3:::snowplow-hosted-assets-ca-central-1",
            "arn:${local.iam_partition}:s3:::snowplow-hosted-assets-ca-central-1/*",
            "arn:${local.iam_partition}:s3:::snowplow-hosted-assets-eu-west-2",
            "arn:${local.iam_partition}:s3:::snowplow-hosted-assets-eu-west-2/*",
            "arn:${local.iam_partition}:s3:::snowplow-hosted-assets-ap-northeast-2",
            "arn:${local.iam_partition}:s3:::snowplow-hosted-assets-ap-northeast-2/*"
          ]
        }
      ]
    )
  })
}

resource "aws_iam_role_policy_attachment" "policy_attachment" {
  role       = aws_iam_role.iam_role.name
  policy_arn = aws_iam_policy.iam_policy.arn
}

resource "aws_iam_instance_profile" "instance_profile" {
  name = var.name
  role = aws_iam_role.iam_role.name
}

# --- EC2: Security Group Rules

resource "aws_security_group" "sg" {
  name   = var.name
  vpc_id = var.vpc_id
  tags   = local.tags
}

resource "aws_security_group_rule" "ingress_tcp_22" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = var.ssh_ip_allowlist
  security_group_id = aws_security_group.sg.id
}

resource "aws_security_group_rule" "egress_tcp_80" {
  type              = "egress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.sg.id
}

resource "aws_security_group_rule" "egress_tcp_443" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.sg.id
}

# Needed for clock synchronization
resource "aws_security_group_rule" "egress_udp_123" {
  type              = "egress"
  from_port         = 123
  to_port           = 123
  protocol          = "udp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.sg.id
}

resource "aws_security_group_rule" "egress_tcp_custom" {
  for_each = toset(var.custom_tcp_egress_port_list)

  type              = "egress"
  from_port         = each.value
  to_port           = each.value
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.sg.id
}

# --- EC2: Launch Templates, Auto-scaling group and Auto-scaling policies

module "instance_type_metrics" {
  source  = "snowplow-devops/ec2-instance-type-metrics/aws"
  version = "0.1.2"

  instance_type = var.instance_type
}

locals {
  hocon = templatefile("${path.module}/templates/config.hocon.tmpl", {
    app_name             = var.name
    in_stream_name       = var.in_stream_name
    enriched_stream_name = var.enriched_stream_name
    bad_stream_name      = var.bad_stream_name
    region               = data.aws_region.current.name
    initial_position     = var.initial_position

    config_hash = local.config_hash

    byte_limit    = var.byte_limit
    record_limit  = var.record_limit
    time_limit_ms = var.time_limit_ms

    assets_update_period = var.assets_update_period

    telemetry_disable          = !var.telemetry_enabled
    telemetry_collector_uri    = join("", module.telemetry.*.collector_uri)
    telemetry_collector_port   = 443
    telemetry_secure           = true
    telemetry_user_provided_id = var.user_provided_id
    telemetry_auto_gen_id      = join("", module.telemetry.*.auto_generated_id)
    telemetry_module_name      = local.module_name
    telemetry_module_version   = local.module_version
  })

  user_data = templatefile("${path.module}/templates/user-data.sh.tmpl", {
    accept_limited_use_license = var.accept_limited_use_license

    config_b64  = var.config_override_b64 == "" ? base64encode(local.hocon) : var.config_override_b64
    version     = local.app_version
    resolver    = "dynamodb:${data.aws_region.current.name}/${aws_dynamodb_table.config.name}/snowplow_resolver"
    enrichments = "dynamodb:${data.aws_region.current.name}/${aws_dynamodb_table.config.name}/snowplow_enrichment_"

    telemetry_script = join("", module.telemetry.*.amazon_linux_2_user_data)

    cloudwatch_logs_enabled   = var.cloudwatch_logs_enabled
    cloudwatch_log_group_name = local.cloudwatch_log_group_name

    container_memory = "${module.instance_type_metrics.memory_application_mb}m"
    java_opts        = var.java_opts

    is_private_ecr_registry = local.is_private_ecr_registry
    private_ecr_registry    = var.private_ecr_registry
    region                  = data.aws_region.current.name
  })
}

module "service" {
  source  = "snowplow-devops/service-ec2/aws"
  version = "0.2.1"

  user_supplied_script = local.user_data
  name                 = var.name
  tags                 = local.tags

  amazon_linux_2_ami_id       = var.amazon_linux_2_ami_id
  instance_type               = var.instance_type
  ssh_key_name                = var.ssh_key_name
  iam_instance_profile_name   = aws_iam_instance_profile.instance_profile.name
  associate_public_ip_address = var.associate_public_ip_address
  security_groups             = [aws_security_group.sg.id]

  min_size   = var.min_size
  max_size   = var.max_size
  subnet_ids = var.subnet_ids

  enable_auto_scaling                 = var.enable_auto_scaling
  scale_up_cooldown_sec               = var.scale_up_cooldown_sec
  scale_up_cpu_threshold_percentage   = var.scale_up_cpu_threshold_percentage
  scale_up_eval_minutes               = var.scale_up_eval_minutes
  scale_down_cooldown_sec             = var.scale_down_cooldown_sec
  scale_down_cpu_threshold_percentage = var.scale_down_cpu_threshold_percentage
  scale_down_eval_minutes             = var.scale_down_eval_minutes
}
