extends RefCounted

## The assistant service's certificate (docs/assistant.md, Security): a 2048-bit RSA key and a self-signed certificate,
## made once on a thread and kept in user:// (owner read and write only). Clients learn its pins when they pair and
## check them on every later connection:
##   pin          "sha256//BASE64": the SHA-256 of the public key (SubjectPublicKeyInfo, DER), as curl's
##                --pinnedpubkey takes it
##   cert_sha256  the SHA-256 of the certificate (DER) in hex, which Python's ssl can check in one line
## Nothing here prints the key.
##
##   var tls := AssistantTls.new()
##   if not tls.load_files(): tls.start_making()      # then poll tls.making() until false, and load_files() again

const KEY_PATH := "user://assistant_tls.key"
const CERT_PATH := "user://assistant_tls.crt"
## Owner read and write: FileAccess.UNIX_READ_OWNER | UNIX_WRITE_OWNER (0600).
const OWNER_ONLY := 256 | 128
const ISSUER := "CN=framecine,O=FrameCine,C=US"

## Tests use other files.
var key_path := KEY_PATH
var cert_path := CERT_PATH
var key: CryptoKey
var cert: X509Certificate
var pin := ""
var cert_sha256 := ""
var error := ""
var _thread: Thread


## Loads the kept key and certificate. False when they are missing or unreadable.
func load_files() -> bool:
	if not FileAccess.file_exists(key_path) or not FileAccess.file_exists(cert_path):
		return false
	var k := CryptoKey.new()
	var c := X509Certificate.new()
	if k.load(key_path) != OK or c.load(cert_path) != OK:
		error = "the certificate files are unreadable; delete them to make new ones"
		return false
	key = k
	cert = c
	pin = public_key_pin(k)
	cert_sha256 = certificate_sha256(c)
	return pin != "" and cert_sha256 != ""


func ready() -> bool:
	return key != null and cert != null


## Makes a new key and certificate on a thread (an RSA key takes a few seconds on the headset).
func start_making() -> void:
	if making():
		return
	_thread = Thread.new()
	_thread.start(_make.bind(key_path, cert_path))


## True while the thread runs; once it ends, call load_files().
func making() -> bool:
	if _thread == null:
		return false
	if _thread.is_alive():
		return true
	var err: String = _thread.wait_to_finish()
	_thread = null
	error = err
	return false


func wait() -> void:
	if _thread != null:
		error = _thread.wait_to_finish()
		_thread = null


static func _make(p_key: String, p_cert: String) -> String:
	var crypto := Crypto.new()
	var k := crypto.generate_rsa(2048)
	if k == null:
		return "could not make a key"
	var c := crypto.generate_self_signed_certificate(k, ISSUER, "20260101000000", "20991231235959")
	if c == null:
		return "could not make a certificate"
	if k.save(p_key) != OK or c.save(p_cert) != OK:
		return "could not write the certificate files"
	owner_only(p_key)
	owner_only(p_cert)
	return ""


static func owner_only(path: String) -> void:
	if OS.get_name() in ["Linux", "macOS", "FreeBSD", "NetBSD", "OpenBSD", "BSD", "Android"]:
		FileAccess.set_unix_permissions(path, OWNER_ONLY)


## "sha256//BASE64" of the key's public half (DER SubjectPublicKeyInfo).
static func public_key_pin(k: CryptoKey) -> String:
	var der := pem_body(k.save_to_string(true))
	return "sha256//" + Marshalls.raw_to_base64(_sha256(der)) if not der.is_empty() else ""


static func certificate_sha256(c: X509Certificate) -> String:
	var der := pem_body(c.save_to_string())
	return _sha256(der).hex_encode() if not der.is_empty() else ""


## The DER bytes inside the first PEM block.
static func pem_body(pem: String) -> PackedByteArray:
	var b64 := ""
	var inside := false
	for line in pem.split("\n"):
		var l := line.strip_edges()
		if l.begins_with("-----BEGIN"):
			inside = true
		elif l.begins_with("-----END"):
			break
		elif inside:
			b64 += l
	return Marshalls.base64_to_raw(b64) if b64 != "" else PackedByteArray()


static func _sha256(data: PackedByteArray) -> PackedByteArray:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(data)
	return h.finish()
