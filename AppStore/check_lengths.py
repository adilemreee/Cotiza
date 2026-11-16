"""Checks every App Store Connect field in AppStoreConnect.md against Apple's limits."""
import re, sys

LIMITS = {"Name": 30, "Subtitle": 30, "Promotional text": 170, "Keywords": 100, "Description": 4000, "What's New": 4000}
text = open("AppStore/AppStoreConnect.md").read()
ok = True
for section in re.split(r"\n## ", text):
    lang = section.split("\n", 1)[0]
    for field, limit in LIMITS.items():
        m = re.search(rf"\*\*{field}\*\*[^\n]*\n```\n(.*?)\n```", section, re.S)
        if not m:
            continue
        value = m.group(1)
        size = len(value.encode()) if field == "Keywords" else len(value)
        status = "OK " if size <= limit else "TOO LONG"
        ok &= size <= limit
        if field == "Keywords" and ", " in value:
            status, ok = "SPACE AFTER COMMA", False
        print(f"{status:9} {lang[:22]:22} {field:17} {size:5}/{limit}")
for name in ["Cotiza Pro Yearly", "Cotiza Pro Monthly", "Cotiza Pro Weekly", "Cotiza Pro Anual", "Cotiza Pro Mensual", "Cotiza Pro Semanal",
             "Cotiza Pro Yıllık", "Cotiza Pro Aylık", "Cotiza Pro Haftalık"]:
    print(f"{'OK ' if len(name) <= 30 else 'TOO LONG':9} IAP display name     {len(name):5}/30  {name}")
for desc in ["Unlimited estimates, invoices and your logo", "Cotizaciones ilimitadas, facturas y tu logo",
             "Sınırsız teklif, fatura ve kendi logon"]:
    ok &= len(desc) <= 45
    print(f"{'OK ' if len(desc) <= 45 else 'TOO LONG':9} IAP description      {len(desc):5}/45  {desc}")
sys.exit(0 if ok else 1)
