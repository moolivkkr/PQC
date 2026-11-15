import ssl, json
c = ssl.create_default_context()
print(json.dumps({"min": str(c.minimum_version), "max": str(c.maximum_version),
  "ciphers": sorted(x["name"] for x in c.get_ciphers()), "options": int(c.options)}))
