# README - Auto Install Script N8n + Chatwoot + Nginx Proxy Manager

## 1. Giới thiệu

Script này giúp bạn cài đặt nhanh **Chatwoot**, **N8n** và **Nginx Proxy Manager (NPM)** trên cùng một server Ubuntu.

* Chatwoot: nền tảng chat & CRM.
* N8n: nền tảng workflow automation.
* Nginx Proxy Manager: quản lý domain, reverse proxy & SSL tự động.

* Phiên bản script:** 2.0
* Tác giả:** Michel Tran
* Website:** [https://phonuiit.com](https://phonuiit.com)

---

## 2. Yêu cầu hệ thống

* Ubuntu 20.04 hoặc 22.04
* Quyền root (sudo)
* Port trống: 80, 81, 443 (NPM), 3000 (Chatwoot), 5678 (N8n), 5432 (Postgres), 6379 (Redis)

---

## 3. Cách sử dụng

1. Upload script `auto_install_chatwoot_customer.sh` lên server và cấp quyền chạy:

```bash
chmod +x auto_install_chatwoot_customer.sh
```

2. Chạy script:

```bash
sudo ./auto_install_chatwoot_customer.sh
```

3. Khi chạy script, nhập các thông tin:

* **Domain Chatwoot:** ví dụ `chat.example.com`
* **Domain N8n:** ví dụ `n8n.example.com`
* **Tiền tố container:** mặc định `services`
* **Port Chatwoot Rails:** mặc định `3000`
* **Port N8n:** mặc định `5678`
* **Port Postgres:** mặc định `5432`
* **Port Redis:** mặc định `6379`

Script sẽ tự động:

* Kiểm tra domain đã trỏ đúng IP server hay chưa
* Tạo thư mục dự án `/home/<container_prefix>`
* Sinh key bảo mật, tạo `.env` cho Chatwoot
* Tạo `docker-compose.yml` cho Chatwoot và N8n
* Cài Docker & Docker Compose nếu chưa có
* Khởi động Chatwoot (Postgres + Redis + Rails + Sidekiq)
* Khởi động N8n, fix quyền `/home/<prefix>/n8n/data`
* Cài Nginx Proxy Manager nếu chưa chạy

---

## 4. Hướng dẫn quản lý

### Xem log container

```bash
docker logs -f <container_name>
```

### Restart dịch vụ

**Chatwoot:**

```bash
cd /home/<prefix>/chatwoot
docker compose restart
```

**N8n:**

```bash
cd /home/<prefix>/n8n
docker compose restart
```

**Nginx Proxy Manager:**

```bash
docker restart npm
```

### Stop tất cả

```bash
cd /home/<prefix>
docker compose -f chatwoot/docker-compose.yml down
docker compose -f n8n/docker-compose.yml down
docker stop npm
```

---

## 5. Truy cập

* **Chatwoot:** http://<domain_chatwoot>:<port> (NPM quản lý domain & SSL)
* **N8n:** http://<domain_n8n>:<port> (NPM quản lý domain & SSL)
* **Nginx Proxy Manager:** http://<server-ip>:81 (admin/changeme)

---

## 6. Ghi chú

* Script đã tự động tạo network Docker chung để NPM proxy trực tiếp bằng **tên container** thay vì IP.
* NPM quản lý SSL, bạn không cần mở port 3000 hay 5678 ra Internet.
* Nếu muốn thay đổi port hoặc domain sau khi cài đặt, chỉnh trên NPM Proxy Host.

---

## 7. Hỗ trợ

Liên hệ: [https://phonuiit.com](https://phonuiit.com)
Chạy trên server Ubuntu, mọi vấn đề về quyền, Docker hoặc firewall đều cần root để sửa.
