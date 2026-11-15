#!/usr/bin/env python3
"""يولّد codeHash لملف license.json العام. الكود نفسه يبقى في المستودع الخاص فقط.

الاستخدام:  python3 tool/license_hash.py HISAB-XXXX
"""
import hashlib, sys

SALT = "hisab-almozaw3:"  # يطابق LicenseService.salt

if len(sys.argv) != 2:
    sys.exit(__doc__)
print(hashlib.sha256((SALT + sys.argv[1].strip().upper()).encode()).hexdigest())
