#!/usr/bin/env python
import sys
from base64 import b64encode
from nacl import encoding, public

def encrypt(public_key: str, secret_value: str) -> str:
    """Encrypt a Unicode string using the public key."""

    public_key = public.PublicKey(public_key.encode("utf-8"), encoding.Base64Encoder())
    sealed_box = public.SealedBox(public_key)
    encrypted = sealed_box.encrypt(secret_value.encode("utf-8"))

    return b64encode(encrypted).decode("utf-8")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python encrypt.py <public_key> <secret_value>")
        sys.exit(1)

    public_key = sys.argv[1]
    secret_value = sys.argv[2]

    encrypted_value = encrypt(public_key, secret_value)
    print(encrypted_value)