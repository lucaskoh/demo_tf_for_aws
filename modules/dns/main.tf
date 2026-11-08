data "aws_route53_zone" "this" {
  name         = var.zone_name
  private_zone = false
}

resource "aws_route53_record" "this" {
  zone_id = data.aws_route53_zone.this.zone_id
  name    = "${var.record_name}.${var.zone_name}"
  type    = var.record_type

  alias {
    name                   = var.alias_dns_name
    zone_id                = var.alias_zone_id
    evaluate_target_health = var.evaluate_target_health
  }
}
