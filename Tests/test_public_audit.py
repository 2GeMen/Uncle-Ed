import importlib.util,tempfile,unittest,json,hashlib
from pathlib import Path
spec=importlib.util.spec_from_file_location('audit',Path(__file__).resolve().parents[1]/'Scripts/audit-public-tree.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class DistributionAuditTests(unittest.TestCase):
 def test_renamed_rom_is_detected(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d)/'innocent.dat';b=bytearray(0x8200);b[4:12]=bytes.fromhex('24ffae51699aa221');p.write_bytes(b)
   self.assertTrue(any('payload' in reason for _,reason in m.audit(d)))
 def test_secret_value_never_leaks(self):
  with tempfile.TemporaryDirectory() as d:
   (Path(d)/'config').write_text('ghp_'+'a'*36)
   rows=m.audit(d);self.assertTrue(rows);self.assertNotIn('a'*36,str(rows))
 def test_unapproved_art_is_blocked(self):
  with tempfile.TemporaryDirectory() as d:
   (Path(d)/'art.png').write_bytes(b'art');self.assertTrue(m.audit(d))
 def test_hash_checked_first_party_art(self):
  with tempfile.TemporaryDirectory() as d:
   r=Path(d);(r/'Shared').mkdir();p=r/'art.png';p.write_bytes(b'art')
   (r/'Shared/asset-provenance.json').write_text(json.dumps({'assets':{'art.png':{'status':'approved','license':'CC0-1.0','sha256':hashlib.sha256(b'art').hexdigest()}}}))
   self.assertEqual(m.audit(d),[]);p.write_bytes(b'changed');self.assertTrue(m.audit(d))
 def test_unready_release_is_blocked(self):
  with tempfile.TemporaryDirectory() as d:self.assertTrue(m.audit(d,True))
if __name__=='__main__':unittest.main()
