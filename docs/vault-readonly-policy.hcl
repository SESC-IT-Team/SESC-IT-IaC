path "kv/data/apps/*" {
  capabilities = ["read"]
}
path "kv/metadata/apps/*" {
  capabilities = ["read", "list"]
}