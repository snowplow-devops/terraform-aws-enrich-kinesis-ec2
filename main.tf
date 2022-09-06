locals {
  module_name    = "enrich-kinesis-ec2"
  module_version = "0.3.1"

  app_name    = "enrich-kinesis"
  app_version = "3.0.3"

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

module "telemetry" {
  source  = "snowplow-devops/telemetry/snowplow"
  version = "0.2.0"

  count = var.telemetry_enabled ? 1 : 0

  user_provided_id = var.user_provided_id
  cloud            = "AWS"
  region           = data.aws_region.current.name
  app_name         = local.app_name
  app_version      = local.app_version
  module_name      = local.module_name
  module_version   = local.module_version
}

data "aws_ami" "amazon_linux_2" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-ebs"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["amazon"]
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
  version = "0.1.1"

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
  version = "0.1.1"

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
  custom_s3_hosted_assets_bucket_policy = <<EOF
    ,{
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:ListBucket"
      ],
      "Effect":"Allow",
      "Resource": [
        "arn:aws:s3:::${var.custom_s3_hosted_assets_bucket_name}",
        "arn:aws:s3:::${var.custom_s3_hosted_assets_bucket_name}/*"
      ]
    }
EOF

  custom_s3_hosted_assets_bucket_policy_final = var.custom_s3_hosted_assets_bucket_name == "" ? "" : local.custom_s3_hosted_assets_bucket_policy
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

  policy = <<EOF
{
  "Version" : "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "kinesis:DescribeStream",
        "kinesis:DescribeStreamSummary",
        "kinesis:List*"
      ],
      "Resource": [
        "arn:aws:kinesis:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:stream/${var.in_stream_name}",
        "arn:aws:kinesis:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:stream/${var.enriched_stream_name}",
        "arn:aws:kinesis:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:stream/${var.bad_stream_name}"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "kinesis:Get*"
      ],
      "Resource": [
        "arn:aws:kinesis:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:stream/${var.in_stream_name}"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "kinesis:Put*"
      ],
      "Resource": [
        "arn:aws:kinesis:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:stream/${var.enriched_stream_name}",
        "arn:aws:kinesis:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:stream/${var.bad_stream_name}"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:BatchWriteItem",
        "dynamodb:PutItem",
        "dynamodb:DescribeTable",
        "dynamodb:DeleteItem",
        "dynamodb:GetItem",
        "dynamodb:Scan",
        "dynamodb:UpdateItem"
      ],
      "Resource": [
        "${aws_dynamodb_table.kcl.arn}"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:DescribeTable",
        "dynamodb:GetItem",
        "dynamodb:Scan"
      ],
      "Resource": [
        "${aws_dynamodb_table.config.arn}"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:PutLogEvents",
        "logs:CreateLogStream",
        "logs:DescribeLogStreams"
      ],
      "Resource": [
        "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:${local.cloudwatch_log_group_name}:*"
      ]
    },
    {
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:ListBucket"
      ],
      "Effect":"Allow",
      "Resource": [
        "arn:aws:s3:::snowplow-hosted-assets",
        "arn:aws:s3:::snowplow-hosted-assets/*",
        "arn:aws:s3:::snowplow-hosted-assets-us-east-1",
        "arn:aws:s3:::snowplow-hosted-assets-us-east-1/*",
        "arn:aws:s3:::snowplow-hosted-assets-us-west-1",
        "arn:aws:s3:::snowplow-hosted-assets-us-west-1/*",
        "arn:aws:s3:::snowplow-hosted-assets-us-west-2",
        "arn:aws:s3:::snowplow-hosted-assets-us-west-2/*",
        "arn:aws:s3:::snowplow-hosted-assets-sa-east-1",
        "arn:aws:s3:::snowplow-hosted-assets-sa-east-1/*",
        "arn:aws:s3:::snowplow-hosted-assets-eu-central-1",
        "arn:aws:s3:::snowplow-hosted-assets-eu-central-1/*",
        "arn:aws:s3:::snowplow-hosted-assets-ap-southeast-1",
        "arn:aws:s3:::snowplow-hosted-assets-ap-southeast-1/*",
        "arn:aws:s3:::snowplow-hosted-assets-ap-southeast-2",
        "arn:aws:s3:::snowplow-hosted-assets-ap-southeast-2/*",
        "arn:aws:s3:::snowplow-hosted-assets-ap-northeast-1",
        "arn:aws:s3:::snowplow-hosted-assets-ap-northeast-1/*",
        "arn:aws:s3:::snowplow-hosted-assets-ap-south-1",
        "arn:aws:s3:::snowplow-hosted-assets-ap-south-1/*",
        "arn:aws:s3:::snowplow-hosted-assets-us-east-2",
        "arn:aws:s3:::snowplow-hosted-assets-us-east-2/*",
        "arn:aws:s3:::snowplow-hosted-assets-ca-central-1",
        "arn:aws:s3:::snowplow-hosted-assets-ca-central-1/*",
        "arn:aws:s3:::snowplow-hosted-assets-eu-west-2",
        "arn:aws:s3:::snowplow-hosted-assets-eu-west-2/*",
        "arn:aws:s3:::snowplow-hosted-assets-ap-northeast-2",
        "arn:aws:s3:::snowplow-hosted-assets-ap-northeast-2/*"
      ]
    }${local.custom_s3_hosted_assets_bucket_policy_final}
  ]
}
EOF
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

# --- EC2: Auto-scaling group & Launch Configurations

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

    disable           = !tobool(var.telemetry_enabled)
    telemetry_url     = join("", module.telemetry.*.collector_uri)
    user_provided_id  = var.user_provided_id
    auto_generated_id = join("", module.telemetry.*.auto_generated_id)
    module_name       = local.module_name
    module_version    = local.module_version
  })

  user_data = templatefile("${path.module}/templates/user-data.sh.tmpl", {
    config      = local.hocon
    version     = local.app_version
    resolver    = "dynamodb:${data.aws_region.current.name}/${aws_dynamodb_table.config.name}/snowplow_resolver"
    enrichments = "dynamodb:${data.aws_region.current.name}/${aws_dynamodb_table.config.name}/snowplow_enrichment_"

    telemetry_script = join("", module.telemetry.*.amazon_linux_2_user_data)

    cloudwatch_logs_enabled   = var.cloudwatch_logs_enabled
    cloudwatch_log_group_name = local.cloudwatch_log_group_name
  })
}

resource "aws_launch_configuration" "lc" {
  name_prefix = "${var.name}-"

  image_id             = var.amazon_linux_2_ami_id == "" ? data.aws_ami.amazon_linux_2.id : var.amazon_linux_2_ami_id
  instance_type        = var.instance_type
  key_name             = var.ssh_key_name
  iam_instance_profile = aws_iam_instance_profile.instance_profile.name
  security_groups      = [aws_security_group.sg.id]
  user_data            = local.user_data

  # Note: Required if deployed in a public subnet
  associate_public_ip_address = var.associate_public_ip_address

  root_block_device {
    volume_type           = "gp2"
    volume_size           = "10"
    delete_on_termination = true
    encrypted             = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

module "tags" {
  source  = "snowplow-devops/tags/aws"
  version = "0.1.1"

  tags = local.tags
}

resource "aws_autoscaling_group" "asg" {
  name = var.name

  max_size = var.max_size
  min_size = var.min_size

  launch_configuration = aws_launch_configuration.lc.name

  health_check_grace_period = 300
  health_check_type         = "EC2"

  vpc_zone_identifier = var.subnet_ids

  enabled_metrics = var.enable_autoscaling_metrics

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 90
    }
    triggers = ["tag"]
  }

  tags = module.tags.asg_tags
}
