[![Release][release-image]][release] [![CI][ci-image]][ci] [![License][license-image]][license] [![Registry][registry-image]][registry] [![Source][source-image]][source]

# terraform-aws-enrich-kinesis-ec2

A Terraform module which deploys Snowplow Enrich service on EC2. If you want to use a custom AMI for this deployment you will need to ensure it is based on top of Amazon Linux 2.

## Telemetry

This module by default collects and forwards telemetry information to Snowplow to understand how our applications are being used.  No identifying information about your sub-account or account fingerprints are ever forwarded to us - it is very simple information about what modules and applications are deployed and active.

If you wish to subscribe to our mailing list for updates to these modules or security advisories please set the `user_provided_id` variable to include a valid email address which we can reach you at.

### How do I disable it?

To disable telemetry simply set variable `telemetry_enabled = false`.

### What are you collecting?

For details on what information is collected please see this module: https://github.com/snowplow-devops/terraform-snowplow-telemetry

## Usage

### Standard usage

Stream Enrich takes data from a raw input stream and pushes validated data to the enriched stream and failed data to the bad stream.  As part of this validation process we leverage Iglu which is Snowplow's schema repository - the home for event and entity definitions.  If you are using custom events that you have defined yourself you will need to ensure that you link in your own Iglu Registries to this module so that they can be discovered correctly.

By default this module enables 5 enrichments which you can find in the `templates/enrichments` directory of this module.

```hcl
module "raw_stream" {
  source  = "snowplow-devops/kinesis-stream/aws"
  version = "0.2.0"

  name = "raw-stream"
}

module "enriched_stream" {
  source  = "snowplow-devops/kinesis-stream/aws"
  version = "0.2.0"

  name = "enriched-stream"
}

module "bad_1_stream" {
  source  = "snowplow-devops/kinesis-stream/aws"
  version = "0.2.0"

  name = "bad-1-stream"
}

module "enrich_kinesis" {
  source = "snowplow-devops/enrich-kinesis-ec2/aws"

  accept_limited_use_license = true

  name                 = "enrich-server"
  vpc_id               = var.vpc_id
  subnet_ids           = var.subnet_ids
  in_stream_name       = module.raw_stream.name
  enriched_stream_name = module.enriched_stream.name
  bad_stream_name      = module.bad_1_stream.name

  ssh_key_name     = "your-key-name"
  ssh_ip_allowlist = ["0.0.0.0/0"]

  # Linking in the custom Iglu Server here
  custom_iglu_resolvers = [
    {
      name            = "Iglu Server"
      priority        = 0
      uri             = "http://your-iglu-server-endpoint/api"
      api_key         = var.iglu_super_api_key
      vendor_prefixes = []
    }
  ]
}
```

### Inserting custom enrichments

To define your own enrichment configurations you will need to provide a JSON encoded string of the enrichment in the appropriate placeholder.

```hcl
locals {
  enrichment_anon_ip = jsonencode(<<EOF
{
  "schema": "iglu:com.snowplowanalytics.snowplow/anon_ip/jsonschema/1-0-1",
  "data": {
    "name": "anon_ip",
    "vendor": "com.snowplowanalytics.snowplow",
    "enabled": true,
    "parameters": {
      "anonOctets": 1,
      "anonSegments": 1
    }
  }
}
EOF
  )
}

module "enrich_kinesis" {
  source = "snowplow-devops/enrich-kinesis-ec2/aws"

  accept_limited_use_license = true

  name                 = "enrich-server"
  vpc_id               = var.vpc_id
  subnet_ids           = var.subnet_ids
  in_stream_name       = module.raw_stream.name
  enriched_stream_name = module.enriched_stream.name
  bad_stream_name      = module.bad_1_stream.name

  ssh_key_name     = "your-key-name"
  ssh_ip_allowlist = ["0.0.0.0/0"]

  # Linking in the custom Iglu Server here
  custom_iglu_resolvers = [
    {
      name            = "Iglu Server"
      priority        = 0
      uri             = "http://your-iglu-server-endpoint/api"
      api_key         = var.iglu_super_api_key
      vendor_prefixes = []
    }
  ]

  # Enable this enrichment
  enrichment_anon_ip = local.enrichment_anon_ip
}
```

### Disabling default enrichments

As with inserting custom enrichments to disable the default enrichments a similar strategy must be employed.  For example to disable YAUAA you would do the following.

```hcl
locals {
  enrichment_yauaa = jsonencode(<<EOF
{
  "schema": "iglu:com.snowplowanalytics.snowplow.enrichments/yauaa_enrichment_config/jsonschema/1-0-0",
  "data": {
    "enabled": false,
    "vendor": "com.snowplowanalytics.snowplow.enrichments",
    "name": "yauaa_enrichment_config"
  }
}
EOF
  )
}

module "enrich_kinesis" {
  source = "snowplow-devops/enrich-kinesis-ec2/aws"

  accept_limited_use_license = true

  name                 = "enrich-server"
  vpc_id               = var.vpc_id
  subnet_ids           = var.subnet_ids
  in_stream_name       = module.raw_stream.name
  enriched_stream_name = module.enriched_stream.name
  bad_stream_name      = module.bad_1_stream.name

  ssh_key_name     = "your-key-name"
  ssh_ip_allowlist = ["0.0.0.0/0"]

  # Linking in the custom Iglu Server here
  custom_iglu_resolvers = [
    {
      name            = "Iglu Server"
      priority        = 0
      uri             = "http://your-iglu-server-endpoint/api"
      api_key         = var.iglu_super_api_key
      vendor_prefixes = []
    }
  ]

  # Disable this enrichment
  enrichment_yauaa_enrichment_config = local.enrichment_yauaa
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 3.72.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 3.72.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_config_autoscaling"></a> [config\_autoscaling](#module\_config\_autoscaling) | snowplow-devops/dynamodb-autoscaling/aws | 0.2.0 |
| <a name="module_instance_type_metrics"></a> [instance\_type\_metrics](#module\_instance\_type\_metrics) | snowplow-devops/ec2-instance-type-metrics/aws | 0.1.2 |
| <a name="module_kcl_autoscaling"></a> [kcl\_autoscaling](#module\_kcl\_autoscaling) | snowplow-devops/dynamodb-autoscaling/aws | 0.2.0 |
| <a name="module_service"></a> [service](#module\_service) | snowplow-devops/service-ec2/aws | 0.2.1 |
| <a name="module_telemetry"></a> [telemetry](#module\_telemetry) | snowplow-devops/telemetry/snowplow | 0.5.0 |

## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_log_group.log_group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_dynamodb_table.config](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table) | resource |
| [aws_dynamodb_table.kcl](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table) | resource |
| [aws_dynamodb_table_item.enrichment_anon_ip](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table_item) | resource |
| [aws_dynamodb_table_item.enrichment_api_request_enrichment_config](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table_item) | resource |
| [aws_dynamodb_table_item.enrichment_campaign_attribution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table_item) | resource |
| [aws_dynamodb_table_item.enrichment_cookie_extractor_config](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table_item) | resource |
| [aws_dynamodb_table_item.enrichment_currency_conversion_config](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table_item) | resource |
| [aws_dynamodb_table_item.enrichment_event_fingerprint_config](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table_item) | resource |
| [aws_dynamodb_table_item.enrichment_http_header_extractor_config](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table_item) | resource |
| [aws_dynamodb_table_item.enrichment_iab_spiders_and_bots_enrichment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table_item) | resource |
| [aws_dynamodb_table_item.enrichment_ip_lookups](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table_item) | resource |
| [aws_dynamodb_table_item.enrichment_javascript_script_config](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table_item) | resource |
| [aws_dynamodb_table_item.enrichment_pii_enrichment_config](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table_item) | resource |
| [aws_dynamodb_table_item.enrichment_referer_parser](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table_item) | resource |
| [aws_dynamodb_table_item.enrichment_sql_query_enrichment_config](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table_item) | resource |
| [aws_dynamodb_table_item.enrichment_ua_parser_config](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table_item) | resource |
| [aws_dynamodb_table_item.enrichment_weather_enrichment_config](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table_item) | resource |
| [aws_dynamodb_table_item.enrichment_yauaa_enrichment_config](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table_item) | resource |
| [aws_dynamodb_table_item.iglu_resolver](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table_item) | resource |
| [aws_iam_instance_profile.instance_profile](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_policy.iam_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.iam_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.policy_attachment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_security_group.sg](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group_rule.egress_tcp_443](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_security_group_rule.egress_tcp_80](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_security_group_rule.egress_tcp_custom](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_security_group_rule.egress_udp_123](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_security_group_rule.ingress_tcp_22](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_bad_stream_name"></a> [bad\_stream\_name](#input\_bad\_stream\_name) | The name of the bad kinesis stream that the Enricher will insert bad data into | `string` | n/a | yes |
| <a name="input_enriched_stream_name"></a> [enriched\_stream\_name](#input\_enriched\_stream\_name) | The name of the enriched kinesis stream that the Enricher will insert validated data into | `string` | n/a | yes |
| <a name="input_in_stream_name"></a> [in\_stream\_name](#input\_in\_stream\_name) | The name of the input kinesis stream that the Enricher will pull data from | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | A name which will be pre-pended to the resources created | `string` | n/a | yes |
| <a name="input_ssh_key_name"></a> [ssh\_key\_name](#input\_ssh\_key\_name) | The name of the SSH key-pair to attach to all EC2 nodes deployed | `string` | n/a | yes |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | The list of subnets to deploy Enrich across | `list(string)` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | The VPC to deploy Enrich within (must have DNS hostnames enabled) | `string` | n/a | yes |
| <a name="input_accept_limited_use_license"></a> [accept\_limited\_use\_license](#input\_accept\_limited\_use\_license) | Acceptance of the SLULA terms (https://docs.snowplow.io/limited-use-license-1.0/) | `bool` | `false` | no |
| <a name="input_amazon_linux_2_ami_id"></a> [amazon\_linux\_2\_ami\_id](#input\_amazon\_linux\_2\_ami\_id) | The AMI ID to use which must be based of of Amazon Linux 2; by default the latest community version is used | `string` | `""` | no |
| <a name="input_app_version"></a> [app\_version](#input\_app\_version) | App version to use. This variable facilitates dev flow, the modules may not work with anything other than the default value. | `string` | `"3.9.0"` | no |
| <a name="input_assets_update_period"></a> [assets\_update\_period](#input\_assets\_update\_period) | Period after which enrich assets should be checked for updates (e.g. MaxMind DB) | `string` | `"7 days"` | no |
| <a name="input_associate_public_ip_address"></a> [associate\_public\_ip\_address](#input\_associate\_public\_ip\_address) | Whether to assign a public ip address to this instance | `bool` | `true` | no |
| <a name="input_byte_limit"></a> [byte\_limit](#input\_byte\_limit) | The amount of bytes to buffer events before pushing them to Kinesis | `number` | `1000000` | no |
| <a name="input_cloudwatch_logs_enabled"></a> [cloudwatch\_logs\_enabled](#input\_cloudwatch\_logs\_enabled) | Whether application logs should be reported to CloudWatch | `bool` | `true` | no |
| <a name="input_cloudwatch_logs_retention_days"></a> [cloudwatch\_logs\_retention\_days](#input\_cloudwatch\_logs\_retention\_days) | The length of time in days to retain logs for | `number` | `7` | no |
| <a name="input_custom_iglu_resolvers"></a> [custom\_iglu\_resolvers](#input\_custom\_iglu\_resolvers) | The custom Iglu Resolvers that will be used by Enrichment to resolve and validate events | <pre>list(object({<br>    name            = string<br>    priority        = number<br>    uri             = string<br>    api_key         = string<br>    vendor_prefixes = list(string)<br>  }))</pre> | `[]` | no |
| <a name="input_custom_s3_hosted_assets_bucket_name"></a> [custom\_s3\_hosted\_assets\_bucket\_name](#input\_custom\_s3\_hosted\_assets\_bucket\_name) | Name of the bucket in which hosted database for the IP Lookups and/or IAB Enrichments are stored | `string` | `""` | no |
| <a name="input_custom_tcp_egress_port_list"></a> [custom\_tcp\_egress\_port\_list](#input\_custom\_tcp\_egress\_port\_list) | For opening up TCP ports to access other destinations not served over HTTP(s) (e.g. for SQL / API enrichments) | `list(string)` | `[]` | no |
| <a name="input_default_iglu_resolvers"></a> [default\_iglu\_resolvers](#input\_default\_iglu\_resolvers) | The default Iglu Resolvers that will be used by Enrichment to resolve and validate events | <pre>list(object({<br>    name            = string<br>    priority        = number<br>    uri             = string<br>    api_key         = string<br>    vendor_prefixes = list(string)<br>  }))</pre> | <pre>[<br>  {<br>    "api_key": "",<br>    "name": "Iglu Central",<br>    "priority": 10,<br>    "uri": "http://iglucentral.com",<br>    "vendor_prefixes": []<br>  },<br>  {<br>    "api_key": "",<br>    "name": "Iglu Central - Mirror 01",<br>    "priority": 20,<br>    "uri": "http://mirror01.iglucentral.com",<br>    "vendor_prefixes": []<br>  }<br>]</pre> | no |
| <a name="input_enable_auto_scaling"></a> [enable\_auto\_scaling](#input\_enable\_auto\_scaling) | Whether to enable auto-scaling policies for the service | `bool` | `true` | no |
| <a name="input_enrichment_anon_ip"></a> [enrichment\_anon\_ip](#input\_enrichment\_anon\_ip) | n/a | `string` | `""` | no |
| <a name="input_enrichment_api_request_enrichment_config"></a> [enrichment\_api\_request\_enrichment\_config](#input\_enrichment\_api\_request\_enrichment\_config) | n/a | `string` | `""` | no |
| <a name="input_enrichment_campaign_attribution"></a> [enrichment\_campaign\_attribution](#input\_enrichment\_campaign\_attribution) | n/a | `string` | `""` | no |
| <a name="input_enrichment_cookie_extractor_config"></a> [enrichment\_cookie\_extractor\_config](#input\_enrichment\_cookie\_extractor\_config) | n/a | `string` | `""` | no |
| <a name="input_enrichment_currency_conversion_config"></a> [enrichment\_currency\_conversion\_config](#input\_enrichment\_currency\_conversion\_config) | n/a | `string` | `""` | no |
| <a name="input_enrichment_event_fingerprint_config"></a> [enrichment\_event\_fingerprint\_config](#input\_enrichment\_event\_fingerprint\_config) | n/a | `string` | `""` | no |
| <a name="input_enrichment_http_header_extractor_config"></a> [enrichment\_http\_header\_extractor\_config](#input\_enrichment\_http\_header\_extractor\_config) | n/a | `string` | `""` | no |
| <a name="input_enrichment_iab_spiders_and_bots_enrichment"></a> [enrichment\_iab\_spiders\_and\_bots\_enrichment](#input\_enrichment\_iab\_spiders\_and\_bots\_enrichment) | Note: Requires paid database to function | `string` | `""` | no |
| <a name="input_enrichment_ip_lookups"></a> [enrichment\_ip\_lookups](#input\_enrichment\_ip\_lookups) | Note: Requires free or paid subscription to database to function | `string` | `""` | no |
| <a name="input_enrichment_javascript_script_config"></a> [enrichment\_javascript\_script\_config](#input\_enrichment\_javascript\_script\_config) | n/a | `string` | `""` | no |
| <a name="input_enrichment_pii_enrichment_config"></a> [enrichment\_pii\_enrichment\_config](#input\_enrichment\_pii\_enrichment\_config) | n/a | `string` | `""` | no |
| <a name="input_enrichment_referer_parser"></a> [enrichment\_referer\_parser](#input\_enrichment\_referer\_parser) | n/a | `string` | `""` | no |
| <a name="input_enrichment_sql_query_enrichment_config"></a> [enrichment\_sql\_query\_enrichment\_config](#input\_enrichment\_sql\_query\_enrichment\_config) | n/a | `string` | `""` | no |
| <a name="input_enrichment_ua_parser_config"></a> [enrichment\_ua\_parser\_config](#input\_enrichment\_ua\_parser\_config) | n/a | `string` | `""` | no |
| <a name="input_enrichment_weather_enrichment_config"></a> [enrichment\_weather\_enrichment\_config](#input\_enrichment\_weather\_enrichment\_config) | n/a | `string` | `""` | no |
| <a name="input_enrichment_yauaa_enrichment_config"></a> [enrichment\_yauaa\_enrichment\_config](#input\_enrichment\_yauaa\_enrichment\_config) | n/a | `string` | `""` | no |
| <a name="input_iam_permissions_boundary"></a> [iam\_permissions\_boundary](#input\_iam\_permissions\_boundary) | The permissions boundary ARN to set on IAM roles created | `string` | `""` | no |
| <a name="input_initial_position"></a> [initial\_position](#input\_initial\_position) | Where to start processing the input Kinesis Stream from (TRIM\_HORIZON or LATEST) | `string` | `"TRIM_HORIZON"` | no |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | The instance type to use | `string` | `"t3a.small"` | no |
| <a name="input_java_opts"></a> [java\_opts](#input\_java\_opts) | Custom JAVA Options | `string` | `"-XX:InitialRAMPercentage=75 -XX:MaxRAMPercentage=75"` | no |
| <a name="input_kcl_read_max_capacity"></a> [kcl\_read\_max\_capacity](#input\_kcl\_read\_max\_capacity) | The maximum READ capacity for the KCL DynamoDB table | `number` | `10` | no |
| <a name="input_kcl_read_min_capacity"></a> [kcl\_read\_min\_capacity](#input\_kcl\_read\_min\_capacity) | The minimum READ capacity for the KCL DynamoDB table | `number` | `1` | no |
| <a name="input_kcl_write_max_capacity"></a> [kcl\_write\_max\_capacity](#input\_kcl\_write\_max\_capacity) | The maximum WRITE capacity for the KCL DynamoDB table | `number` | `10` | no |
| <a name="input_kcl_write_min_capacity"></a> [kcl\_write\_min\_capacity](#input\_kcl\_write\_min\_capacity) | The minimum WRITE capacity for the KCL DynamoDB table | `number` | `1` | no |
| <a name="input_max_size"></a> [max\_size](#input\_max\_size) | The maximum number of servers in this server-group | `number` | `2` | no |
| <a name="input_min_size"></a> [min\_size](#input\_min\_size) | The minimum number of servers in this server-group | `number` | `1` | no |
| <a name="input_record_limit"></a> [record\_limit](#input\_record\_limit) | The number of events to buffer before pushing them to Kinesis | `number` | `500` | no |
| <a name="input_scale_down_cooldown_sec"></a> [scale\_down\_cooldown\_sec](#input\_scale\_down\_cooldown\_sec) | Time (in seconds) until another scale-down action can occur | `number` | `600` | no |
| <a name="input_scale_down_cpu_threshold_percentage"></a> [scale\_down\_cpu\_threshold\_percentage](#input\_scale\_down\_cpu\_threshold\_percentage) | The average CPU percentage that we must be below to scale-down | `number` | `20` | no |
| <a name="input_scale_down_eval_minutes"></a> [scale\_down\_eval\_minutes](#input\_scale\_down\_eval\_minutes) | The number of consecutive minutes that we must be below the threshold to scale-down | `number` | `60` | no |
| <a name="input_scale_up_cooldown_sec"></a> [scale\_up\_cooldown\_sec](#input\_scale\_up\_cooldown\_sec) | Time (in seconds) until another scale-up action can occur | `number` | `180` | no |
| <a name="input_scale_up_cpu_threshold_percentage"></a> [scale\_up\_cpu\_threshold\_percentage](#input\_scale\_up\_cpu\_threshold\_percentage) | The average CPU percentage that must be exceeded to scale-up | `number` | `60` | no |
| <a name="input_scale_up_eval_minutes"></a> [scale\_up\_eval\_minutes](#input\_scale\_up\_eval\_minutes) | The number of consecutive minutes that the threshold must be breached to scale-up | `number` | `5` | no |
| <a name="input_ssh_ip_allowlist"></a> [ssh\_ip\_allowlist](#input\_ssh\_ip\_allowlist) | The list of CIDR ranges to allow SSH traffic from | `list(any)` | <pre>[<br>  "0.0.0.0/0"<br>]</pre> | no |
| <a name="input_tags"></a> [tags](#input\_tags) | The tags to append to this resource | `map(string)` | `{}` | no |
| <a name="input_telemetry_enabled"></a> [telemetry\_enabled](#input\_telemetry\_enabled) | Whether or not to send telemetry information back to Snowplow Analytics Ltd | `bool` | `true` | no |
| <a name="input_time_limit_ms"></a> [time\_limit\_ms](#input\_time\_limit\_ms) | The amount of time to buffer events before pushing them to Kinesis | `number` | `500` | no |
| <a name="input_user_provided_id"></a> [user\_provided\_id](#input\_user\_provided\_id) | An optional unique identifier to identify the telemetry events emitted by this stack | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_asg_id"></a> [asg\_id](#output\_asg\_id) | ID of the ASG |
| <a name="output_asg_name"></a> [asg\_name](#output\_asg\_name) | Name of the ASG |
| <a name="output_sg_id"></a> [sg\_id](#output\_sg\_id) | ID of the security group attached to the Enrich servers |

# Copyright and license

Copyright 2021-current Snowplow Analytics Ltd.

Licensed under the [Snowplow Limited Use License Agreement][license]. _(If you are uncertain how it applies to your use case, check our answers to [frequently asked questions][license-faq].)_

[release]: https://github.com/snowplow-devops/terraform-aws-enrich-kinesis-ec2/releases/latest
[release-image]: https://img.shields.io/github/v/release/snowplow-devops/terraform-aws-enrich-kinesis-ec2

[ci]: https://github.com/snowplow-devops/terraform-aws-enrich-kinesis-ec2/actions?query=workflow%3Aci
[ci-image]: https://github.com/snowplow-devops/terraform-aws-enrich-kinesis-ec2/workflows/ci/badge.svg

[license]: https://docs.snowplow.io/limited-use-license-1.0/
[license-image]: https://img.shields.io/badge/license-Snowplow--Limited--Use-blue.svg?style=flat
[license-faq]: https://docs.snowplow.io/docs/contributing/limited-use-license-faq/

[registry]: https://registry.terraform.io/modules/snowplow-devops/enrich-kinesis-ec2/aws/latest
[registry-image]: https://img.shields.io/static/v1?label=Terraform&message=Registry&color=7B42BC&logo=terraform

[source]: https://github.com/snowplow/enrich
[source-image]: https://img.shields.io/static/v1?label=Snowplow&message=Enrich&color=0E9BA4&logo=GitHub
