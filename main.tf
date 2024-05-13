resource "random_string" "random" {
  length    = 8
  special   = false
  min_lower = 8
}


resource "google_storage_bucket" "static_site" {
  name                        = "cloudroot-demo-${random_string.random.result}"
  location                    = "US"
  force_destroy               = true
  uniform_bucket_level_access = true

  website {
    main_page_suffix = "index.html"
    not_found_page   = "404.html"
  }

  labels = {
    allow_public_bucket_acl = "true"
  }

  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    response_header = ["*"]
    max_age_seconds = 3600

  }
  lifecycle_rule {
    condition {
      num_newer_versions = 2
    }
    action {
      type = "Delete"
    }
  }
}


resource "google_storage_bucket_object" "static_site_src" {
  name   = "index.html"
  source = "index.html"
  bucket = google_storage_bucket.static_site.name
}

resource "google_storage_bucket_object" "static_site_404" {
  name   = "404.html"
  source = "404.html"
  bucket = google_storage_bucket.static_site.name
}

resource "google_storage_bucket_iam_member" "viewers" {
  bucket = google_storage_bucket.static_site.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
  depends_on = [
    google_storage_bucket_object.static_site_src,
    google_storage_bucket_object.static_site_404,
    google_storage_bucket.static_site
  ]
}

# Add the bucket as a CDN backend
resource "google_compute_backend_bucket" "website" {
  name        = "website-backend"
  description = "Contains files needed by the website"
  bucket_name = google_storage_bucket.static_site.name
  enable_cdn  = true
}

# GCP URL MAP
resource "google_compute_url_map" "website" {
  name            = "website-url-map"
  default_service = google_compute_backend_bucket.website.self_link
}

#HTTP access 
resource "google_compute_target_http_proxy" "website_http" {
  name    = "website-target-http-proxy"
  url_map = google_compute_url_map.website.self_link
}

resource "google_compute_global_address" "website" {
  name = "website-lb-ip"
}

# GCP forwarding rule for HTTP 
resource "google_compute_global_forwarding_rule" "http" {
  name                  = "website-forwarding-rule-http"
  load_balancing_scheme = "EXTERNAL"
  ip_address            = google_compute_global_address.website.address
  ip_protocol           = "TCP"
  port_range            = "80"
  target                = google_compute_target_http_proxy.website_http.self_link
}


data "google_dns_managed_zone" "env_dns_zone" {
  name = "my-cloudrroot7-domain-zone"
}

resource "google_dns_record_set" "website" {
  provider     = google
  name         = "web.${data.google_dns_managed_zone.env_dns_zone.dns_name}"
  type         = "A"
  ttl          = 300
  managed_zone = data.google_dns_managed_zone.env_dns_zone.name
  rrdatas      = [google_compute_global_address.website.address]
}