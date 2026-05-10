import requests
import json
import time
import os

SUPABASE_URL = "https://mroesvsmylnaxelrhqtl.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1yb2VzdnNteWxuYXhlbHJocXRsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE3ODY4NTksImV4cCI6MjA4NzM2Mjg1OX0.MFsx8h7CIVpDBC23JJ_5NRD0MFPFSIs55N_rXdgTXtU"

SELFIE_PATH = "/home/servirce/.gemini/antigravity/brain/c3391644-26c0-4896-aaba-6339bc791c4c/test_selfie_driver_1773289822849.png"
CNH_PATH = "/home/servirce/.gemini/antigravity/brain/c3391644-26c0-4896-aaba-6339bc791c4c/test_cnh_card_1773289846065.png"

def upload_file(local_path, remote_name):
    url = f"{SUPABASE_URL}/storage/v1/object/id-verification/{remote_name}"
    headers = {
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "apikey": SUPABASE_KEY,
        "Content-Type": "image/png"
    }
    with open(local_path, "rb") as f:
        data = f.read()
    
    print(f"Uploading {local_path} to {remote_name}...")
    response = requests.post(url, headers=headers, data=data)
    if response.status_code == 200:
        print(f"✅ Upload success: {remote_name}")
        return f"id-verification/{remote_name}"
    else:
        print(f"❌ Upload failed: {response.status_code} - {response.text}")
        # Se já existe, tenta o POST (upsert não é padrão via rest simples sem query params, mas vamos tentar)
        return None

def verify_face(cnh_path, selfie_path):
    url = f"{SUPABASE_URL}/functions/v1/verify-face"
    headers = {
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "apikey": SUPABASE_KEY,
        "Content-Type": "application/json"
    }
    payload = {
        "cnhPath": cnh_path,
        "selfiePath": selfie_path
    }
    print(f"Calling verify-face with payload: {json.dumps(payload, indent=2)}")
    response = requests.post(url, headers=headers, json=payload)
    return response

if __name__ == "__main__":
    ts = int(time.time())
    remote_selfie = f"test/selfie_{ts}.png"
    remote_cnh = f"test/cnh_{ts}.png"
    
    p1 = upload_file(SELFIE_PATH, remote_selfie)
    p2 = upload_file(CNH_PATH, remote_cnh)
    
    if p1 and p2:
        res = verify_face(p2, p1) # p2 is CNH, p1 is Selfie
        print(f"\n--- Result ---")
        print(f"Status: {res.status_code}")
        res_data = res.json()
        print(f"Match: {res_data.get('match')}")
        print(f"Similarity: {res_data.get('similarity')}")
        
        extracted = res_data.get('extractedData')
        if extracted:
            print("\n📝 Dados Extraídos (OCR):")
            print(f"Nome: {extracted.get('fullName')}")
            print(f"CPF: {extracted.get('cpf')}")
            print(f"Nascimento: {extracted.get('dob')}")
            print(f"Registro: {extracted.get('licenseNumber')}")
        else:
            print("\n⚠️ Nenhum dado extraído pelo OCR.")
    else:
        print("Aborting due to upload failure.")
