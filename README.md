# SUMI GĐ0: hợp đồng

Giải nén vào repo `sumi`, rồi commit.

```
docs/      3 schema + CONVENTIONS.md, APP_API.md, OBJECT_API.md
examples/  manifest mẫu của kakunin, jigen; index.json; config.json
tools/     validate.py
```

Kiểm tra: `python3 tools/validate.py all` (cần `pip install jsonschema`).

Lưu ý: manifest mẫu của kakunin và jigen là **tạm**, viết theo plan. Bản thật sẽ chốt ở GĐ1 sau khi đọc code hiện tại.
`sha` trong `examples/index.json` là giá trị giả (toàn số 0), chỉ để kiểm tra định dạng.
