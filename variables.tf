variable "accept_limited_use_license" {
  description = "Acceptance of the SLULA terms (https://docs.snowplow.io/limited-use-license-1.0/)"
  type        = bool
  default     = false

  validation {
    condition     = var.accept_limited_use_license
    error_message = "Please accept the terms of the Snowplow Limited Use License Agreement to proceed."
  }
}

variable "name" {
  description = "A name which will be pre-pended to the resources created"
  type        = string
}

variable "app_version" {
  description = "App version to use. This variable facilitates dev flow, the modules may not work with anything other than the default value."
  type        = string
  default     = "3.9.0"
}

variable "config_override_b64" {
  description = "App config uploaded as a base64 encoded blob. This variable facilitates dev flow, if config is incorrect this can break the deployment."
  type        = string
  default     = ""
}

variable "vpc_id" {
  description = "The VPC to deploy Enrich within (must have DNS hostnames enabled)"
  type        = string
}

variable "subnet_ids" {
  description = "The list of subnets to deploy Enrich across"
  type        = list(string)
}

variable "instance_type" {
  description = "The instance type to use"
  type        = string
  default     = "t3a.small"
}

variable "associate_public_ip_address" {
  description = "Whether to assign a public ip address to this instance"
  type        = bool
  default     = true
}

variable "ssh_key_name" {
  description = "The name of the SSH key-pair to attach to all EC2 nodes deployed"
  type        = string
}

variable "ssh_ip_allowlist" {
  description = "The list of CIDR ranges to allow SSH traffic from"
  type        = list(any)
  default     = ["0.0.0.0/0"]
}

variable "iam_permissions_boundary" {
  description = "The permissions boundary ARN to set on IAM roles created"
  default     = ""
  type        = string
}

variable "min_size" {
  description = "The minimum number of servers in this server-group"
  default     = 1
  type        = number
}

variable "max_size" {
  description = "The maximum number of servers in this server-group"
  default     = 2
  type        = number
}

variable "amazon_linux_2_ami_id" {
  description = "The AMI ID to use which must be based of of Amazon Linux 2; by default the latest community version is used"
  default     = ""
  type        = string
}

variable "kcl_read_min_capacity" {
  description = "The minimum READ capacity for the KCL DynamoDB table"
  type        = number
  default     = 1
}

variable "kcl_read_max_capacity" {
  description = "The maximum READ capacity for the KCL DynamoDB table"
  type        = number
  default     = 10
}

variable "kcl_write_min_capacity" {
  description = "The minimum WRITE capacity for the KCL DynamoDB table"
  type        = number
  default     = 1
}

variable "kcl_write_max_capacity" {
  description = "The maximum WRITE capacity for the KCL DynamoDB table"
  type        = number
  default     = 10
}

variable "tags" {
  description = "The tags to append to this resource"
  default     = {}
  type        = map(string)
}

variable "cloudwatch_logs_enabled" {
  description = "Whether application logs should be reported to CloudWatch"
  default     = true
  type        = bool
}

variable "cloudwatch_logs_retention_days" {
  description = "The length of time in days to retain logs for"
  default     = 7
  type        = number
}

variable "java_opts" {
  description = "Custom JAVA Options"
  default     = "-XX:InitialRAMPercentage=75 -XX:MaxRAMPercentage=75"
  type        = string
}

# --- Auto-scaling options

variable "enable_auto_scaling" {
  description = "Whether to enable auto-scaling policies for the service"
  default     = true
  type        = bool
}

variable "scale_up_cooldown_sec" {
  description = "Time (in seconds) until another scale-up action can occur"
  default     = 180
  type        = number
}

variable "scale_up_cpu_threshold_percentage" {
  description = "The average CPU percentage that must be exceeded to scale-up"
  default     = 60
  type        = number
}

variable "scale_up_eval_minutes" {
  description = "The number of consecutive minutes that the threshold must be breached to scale-up"
  default     = 5
  type        = number
}

variable "scale_down_cooldown_sec" {
  description = "Time (in seconds) until another scale-down action can occur"
  default     = 600
  type        = number
}

variable "scale_down_cpu_threshold_percentage" {
  description = "The average CPU percentage that we must be below to scale-down"
  default     = 20
  type        = number
}

variable "scale_down_eval_minutes" {
  description = "The number of consecutive minutes that we must be below the threshold to scale-down"
  default     = 60
  type        = number
}

# --- Configuration options

variable "in_stream_name" {
  description = "The name of the input kinesis stream that the Enricher will pull data from"
  type        = string
}

variable "enriched_stream_name" {
  description = "The name of the enriched kinesis stream that the Enricher will insert validated data into"
  type        = string
}

variable "bad_stream_name" {
  description = "The name of the bad kinesis stream that the Enricher will insert bad data into"
  type        = string
}

variable "initial_position" {
  description = "Where to start processing the input Kinesis Stream from (TRIM_HORIZON or LATEST)"
  default     = "TRIM_HORIZON"
  type        = string
}

variable "byte_limit" {
  description = "The amount of bytes to buffer events before pushing them to Kinesis"
  default     = 1000000
  type        = number
}

variable "record_limit" {
  description = "The number of events to buffer before pushing them to Kinesis"
  default     = 500
  type        = number
}

variable "time_limit_ms" {
  description = "The amount of time to buffer events before pushing them to Kinesis"
  default     = 500
  type        = number
}

variable "assets_update_period" {
  description = "Period after which enrich assets should be checked for updates (e.g. MaxMind DB)"
  default     = "7 days"
  type        = string

  validation {
    condition     = can(regex("\\d+ (ns|nano|nanos|nanosecond|nanoseconds|us|micro|micros|microsecond|microseconds|ms|milli|millis|millisecond|milliseconds|s|second|seconds|m|minute|minutes|h|hour|hours|d|day|days)", var.assets_update_period))
    error_message = "Invalid period formant."
  }
}

# --- Enrichment options
#
# To take full advantage of Snowplows enrichments should be activated to enhance and extend the data included
# with each event passing through the pipeline.  By default this module deploys the following:
#
# - campaign_attribution
# - event_fingerprint_config
# - referer_parser
# - ua_parser_config
# - yauaa_enrichment_config
#
# You can override the configuration JSON for any of these auto-enabled enrichments to turn them off or change the parameters
# along with activating any of available enrichments in our estate by passing in the appropriate configuration JSON.
#
# NOTE: All supplied JSONs should be `jsonencoded` _before_ being passed to this module so that they can be safely uploaded.
#       An example of how to override the input is supplied below.
#
# enrichment_yauaa_enrichment_config = jsonencode(<<EOF
# {
#   "schema": "iglu:com.snowplowanalytics.snowplow.enrichments/yauaa_enrichment_config/jsonschema/1-0-0",
#   "data": {
#     "enabled": false,
#     "vendor": "com.snowplowanalytics.snowplow.enrichments",
#     "name": "yauaa_enrichment_config"
#   }
# }
# EOF
#   )

variable "custom_s3_hosted_assets_bucket_name" {
  description = "Name of the bucket in which hosted database for the IP Lookups and/or IAB Enrichments are stored"
  default     = ""
  type        = string
}

variable "custom_tcp_egress_port_list" {
  description = "For opening up TCP ports to access other destinations not served over HTTP(s) (e.g. for SQL / API enrichments)"
  default     = []
  type        = list(string)
}

# --- Iglu Resolver

variable "default_iglu_resolvers" {
  description = "The default Iglu Resolvers that will be used by Enrichment to resolve and validate events"
  default = [
    {
      name            = "Iglu Central"
      priority        = 10
      uri             = "http://iglucentral.com"
      api_key         = ""
      vendor_prefixes = []
    },
    {
      name            = "Iglu Central - Mirror 01"
      priority        = 20
      uri             = "http://mirror01.iglucentral.com"
      api_key         = ""
      vendor_prefixes = []
    }
  ]
  type = list(object({
    name            = string
    priority        = number
    uri             = string
    api_key         = string
    vendor_prefixes = list(string)
  }))
}

variable "custom_iglu_resolvers" {
  description = "The custom Iglu Resolvers that will be used by Enrichment to resolve and validate events"
  default     = []
  type = list(object({
    name            = string
    priority        = number
    uri             = string
    api_key         = string
    vendor_prefixes = list(string)
  }))
}

# --- Enrichments which are enabled by default

variable "enrichment_campaign_attribution" {
  default = ""
  type    = string
}

variable "enrichment_event_fingerprint_config" {
  default = ""
  type    = string
}

variable "enrichment_referer_parser" {
  default = ""
  type    = string
}

variable "enrichment_ua_parser_config" {
  default = ""
  type    = string
}

variable "enrichment_yauaa_enrichment_config" {
  default = ""
  type    = string
}

# --- Enrichments which are disabled by default

variable "enrichment_anon_ip" {
  default = ""
  type    = string
}

variable "enrichment_api_request_enrichment_config" {
  default = ""
  type    = string
}

variable "enrichment_cookie_extractor_config" {
  default = ""
  type    = string
}

variable "enrichment_currency_conversion_config" {
  default = ""
  type    = string
}

variable "enrichment_http_header_extractor_config" {
  default = ""
  type    = string
}

# Note: Requires paid database to function
variable "enrichment_iab_spiders_and_bots_enrichment" {
  default = ""
  type    = string
}

# Note: Requires free or paid subscription to database to function
variable "enrichment_ip_lookups" {
  default = ""
  type    = string
}

variable "enrichment_javascript_script_config" {
  default = ""
  type    = string
}

variable "enrichment_pii_enrichment_config" {
  default = ""
  type    = string
}

variable "enrichment_sql_query_enrichment_config" {
  default = ""
  type    = string
}

variable "enrichment_weather_enrichment_config" {
  default = ""
  type    = string
}

# --- Telemetry

variable "telemetry_enabled" {
  description = "Whether or not to send telemetry information back to Snowplow Analytics Ltd"
  type        = bool
  default     = true
}

variable "user_provided_id" {
  description = "An optional unique identifier to identify the telemetry events emitted by this stack"
  type        = string
  default     = ""
}

# --- Image Repositories

variable "private_ecr_registry" {
  description = "The URL of an ECR registry that the sub-account has access to (e.g. '000000000000.dkr.ecr.cn-north-1.amazonaws.com.cn/')"
  type        = string
  default     = ""
}
