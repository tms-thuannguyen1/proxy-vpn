# L2TP/IPsec VPN Client & SOCKS5 Proxy (Docker)

Giải pháp kết nối VPN L2TP/IPsec ổn định trên macOS thông qua Docker container. Toàn bộ lưu lượng VPN được đóng gói thành cổng **SOCKS5 Proxy (`127.0.0.1:1080`)** trên máy của bạn, giải quyết triệt để vấn đề kẹt mạng hoặc không tương thích thuật toán mã hóa (3DES/SHA1) của macOS.

```
Trình duyệt / macOS ──SOCKS5──▶ 127.0.0.1:1080 ──▶ [Docker: microsocks → ppp0 (L2TP) → IPsec] ──▶ VPN Server
```

## Mục lục

1. [Yêu cầu chuẩn bị](#1-yêu-cầu-chuẩn-bị)
2. [Cấu hình thông tin tài khoản](#2-cấu-hình-thông-tin-tài-khoản)
3. [Khởi chạy lần đầu](#3-khởi-chạy-lần-đầu)
4. [Cách sử dụng mạng qua Proxy](#4-cách-sử-dụng-mạng-qua-proxy)
5. [Bật / Tắt hàng ngày](#5-bật--tắt-hàng-ngày)
6. [Phím tắt Terminal (zsh)](#6-phím-tắt-terminal-zsh)
7. [Xử lý sự cố thường gặp](#7-xử-lý-sự-cố-thường-gặp)

## Cấu trúc dự án

| File                 | Vai trò                                                              |
| -------------------- | -------------------------------------------------------------------- |
| `Dockerfile`         | Image Alpine: strongSwan (IPsec), xl2tpd, ppp, microsocks            |
| `entrypoint.sh`      | Sinh cấu hình IPsec/L2TP từ biến môi trường, dựng tunnel, chạy proxy |
| `docker-compose.yml` | Khai báo service, cổng proxy; nạp tài khoản từ `.env`                |
| `.env.example`       | Mẫu tài khoản VPN — copy thành `.env` (`.env` bị git bỏ qua)         |
| `vpn.zsh`            | Phím tắt Terminal: `vpn-on`, `vpn-off`, `vpn-status`, `vpn-logs`     |

---

## 1. Yêu cầu chuẩn bị

- Máy đã cài đặt và đang bật **Docker Desktop**.
- Đã clone hoặc tải thư mục mã nguồn này về máy (khuyến nghị đặt tại `~/l2tp-proxy`).

## 2. Cấu hình thông tin tài khoản

Tài khoản VPN được đặt trong file `.env` (không nằm trong `docker-compose.yml`). Tạo file từ mẫu:

```bash
cp .env.example .env
```

Mở `.env` và thay các trường thông tin bằng tài khoản VPN bạn được cấp:

```bash
VPN_SERVER=your_vpn_server_ip      # IP hoặc Domain máy chủ VPN
VPN_PSK=your_preshared_key         # Khóa chia sẻ trước (Secret / PSK)
VPN_USER=your_vpn_username         # Tên tài khoản VPN
VPN_PASSWORD=your_vpn_password     # Mật khẩu VPN
```

`docker-compose.yml` tự nạp file này qua `env_file: .env`.

> [!WARNING]
> Không commit file chứa tài khoản/mật khẩu cá nhân lên các kho mã nguồn công khai (public git). File `.env` đã được liệt kê trong `.gitignore` — đừng gỡ dòng đó và đừng dùng `git add -f .env`.

## 3. Khởi chạy lần đầu

Mở Terminal tại thư mục dự án và chạy:

```bash
docker compose up -d --build
```

Chờ khoảng **5–10 giây** để container khởi động và bắt tay với server VPN, sau đó kiểm tra kết nối:

```bash
curl --socks5-hostname 127.0.0.1:1080 https://ipinfo.io/ip
```

Nếu Terminal in ra **địa chỉ IP của server khách hàng**, kết nối đã sẵn sàng sử dụng.

## 4. Cách sử dụng mạng qua Proxy

Chọn **1 trong 2 cách** bên dưới tùy theo nhu cầu.

### Cách 1: Chỉ dùng cho Trình duyệt

Không ảnh hưởng đến mạng chung của máy (Zoom, Meet, YouTube, Slack vẫn dùng mạng cá nhân bình thường).

1. Cài extension **ZeroOmega** (hoặc **Proxy SwitchyOmega**) trên Chrome / Brave / Edge.
2. Mở cài đặt extension, thêm profile mới:

   | Trường       | Giá trị      |
   | ------------ | ------------ |
   | Profile name | `Client VPN` |
   | Protocol     | `SOCKS5`     |
   | Server       | `127.0.0.1`  |
   | Port         | `1080`       |

3. Nhấn **Apply changes** để lưu.

- **Khi làm việc:** Bấm vào biểu tượng tiện ích trên thanh công cụ và chọn **Client VPN**.
- **Khi nghỉ:** Chọn **[Direct]** để quay về mạng thông thường.

### Cách 2: Đổi IP cho toàn bộ máy Mac

1. Vào **System Settings → Network →** chọn mạng đang dùng (Wi-Fi hoặc Ethernet) **→ Details...**
2. Chọn thẻ **Proxies** ở danh sách bên trái.
3. Bật mục **SOCKS proxy**:
   - Server: `127.0.0.1`
   - Port: `1080`
4. Bấm **OK → Apply**.

> [!TIP]
> Có thể tự động hóa toàn bộ bước này bằng lệnh `vpn-on` / `vpn-off` — xem [mục 6](#6-phím-tắt-terminal-zsh).

## 5. Bật / Tắt hàng ngày

**Khi không làm việc (Tắt VPN):**

```bash
docker compose stop
```

> [!IMPORTANT]
> Nếu dùng **Cách 2**, nhớ gạt tắt SOCKS proxy trong cài đặt macOS để tránh bị rớt mạng.

**Khi cần làm việc (Bật lại VPN):**

```bash
docker compose start
```

Chờ khoảng **10–15 giây** là proxy `1080` sẽ hoạt động trở lại (container kết nối lại IPsec + L2TP từ đầu).

## 6. Phím tắt Terminal (zsh)

File `vpn.zsh` cung cấp sẵn các lệnh tắt, dùng được từ **bất kỳ thư mục nào** trong Terminal.

### Cài đặt

Thêm dòng sau vào cuối `~/.zshrc` (sửa đường dẫn nếu bạn đặt dự án ở chỗ khác):

```bash
source ~/l2tp-proxy/vpn.zsh
```

Nạp lại cấu hình:

```bash
source ~/.zshrc
```

### Các lệnh

| Lệnh               | Chức năng                                                                                   |
| ------------------ | ------------------------------------------------------------------------------------------- |
| `vpn-on`           | Bật container, **chờ đến khi proxy thực sự thông**, rồi bật SOCKS proxy cho macOS (Cách 2)  |
| `vpn-on --browser` | Chỉ bật container, không đụng cài đặt mạng macOS (dùng với extension — Cách 1)              |
| `vpn-off`          | Tắt SOCKS proxy macOS trên **mọi** network service, rồi dừng container                      |
| `vpn-status`       | Xem trạng thái container, IP đầu ra qua proxy, và service nào đang bật SOCKS proxy          |
| `vpn-logs`         | Xem log container theo thời gian thực                                                       |

### Điểm cải tiến so với script đơn giản

- **Không `cd`**: gọi `docker compose -f <dir>/docker-compose.yml`, Terminal vẫn giữ nguyên thư mục hiện tại.
- **Tự dò network service đang dùng** (Wi-Fi / Ethernet / USB LAN...) theo default route, không hardcode `Wi-Fi`.
- **Chờ proxy sẵn sàng thật** (thử `curl` qua proxy mỗi giây, tối đa 30 giây) thay vì `sleep 3` cố định. Nếu VPN không lên, **không** bật proxy macOS → tránh mất mạng toàn máy.
- **`vpn-off` tắt proxy trên mọi service** đang bật, phòng trường hợp bạn đổi Wi-Fi ↔ Ethernet trong lúc VPN chạy.
- **`up -d` thay cho `start`**: chạy được cả khi container chưa từng được tạo hoặc đã bị xóa.
- Kiểm tra Docker Desktop đã chạy chưa trước khi thao tác.

### Tùy chỉnh (tùy chọn)

Đặt biến **trước** dòng `source` trong `~/.zshrc`:

```bash
export VPN_NET_SERVICE="Wi-Fi"      # Ép dùng 1 network service cố định (mặc định: tự dò)
export VPN_PROXY_TIMEOUT=60         # Thời gian tối đa chờ proxy, giây (mặc định: 30)
export VPN_PROXY_PORT=1080          # Cổng proxy (mặc định: 1080)
export VPN_PROXY_DIR=~/l2tp-proxy   # Thư mục dự án (mặc định: thư mục chứa vpn.zsh)
source ~/l2tp-proxy/vpn.zsh
```

> [!NOTE]
> Lệnh `networksetup` có thể hiện hộp thoại yêu cầu mật khẩu macOS ở lần đầu thay đổi cài đặt mạng.

## 7. Xử lý sự cố thường gặp

**Xem log chi tiết của container:**

```bash
docker logs -f l2tp-proxy
# hoặc
vpn-logs
```

**Tra lỗi theo log:** khi kết nối thất bại, log in dòng `ERROR: ...` kèm các dòng ngay phía trên cho biết nguyên nhân:

| Dòng log | Nguyên nhân | Cách xử lý |
| --- | --- | --- |
| `peer not responding` / `giving up after 5 retransmits` | Không tới được server IPsec | Kiểm tra `VPN_SERVER`; mạng đang dùng có chặn UDP 500/4500 không |
| `NO_PROPOSAL_CHOSEN` | Server không hỗ trợ bộ mã hóa đang cấu hình | Gửi log cho người quản trị để bổ sung `ike=`/`esp=` trong `entrypoint.sh` |
| `IDir '...' does not match to '...'` | Server nằm sau NAT, tự nhận bằng IP nội bộ | Đã xử lý sẵn (`rightid=%any`); nếu vẫn gặp, chạy lại `git pull` và `docker compose up -d --build` |
| `INVALID_HASH_INFORMATION` / `AUTHENTICATION_FAILED` | Sai `VPN_PSK` | Kiểm tra lại PSK |
| `Connecting to host ... port 1701` nhưng không có `Connection established` | L2TP không được server trả lời | Kiểm tra IPsec phía trên đã `established successfully` chưa |
| `You are already logged in - access denied` | Tài khoản đang có phiên khác trên server | Chờ 1–2 phút (phiên cũ hết hạn), hoặc tắt máy khác đang dùng cùng tài khoản |
| `CHAP authentication failed` (không kèm dòng trên) | Sai `VPN_USER` / `VPN_PASSWORD` | Kiểm tra lại tài khoản |

Container tự thử lại sau mỗi lần lỗi (`restart: unless-stopped`). Nếu lỗi do cấu hình, dừng hẳn bằng `docker compose stop`, sửa `.env`, rồi `docker compose up -d`.

**Lỗi `curl: (97) connection to proxy closed`:**

Proxy chưa sẵn sàng (VPN chưa kết nối xong hoặc đang lỗi). Xem log theo bảng trên; kiểm tra `VPN_SERVER`, `VPN_PSK`, `VPN_USER`, `VPN_PASSWORD` trong `.env` có bị thừa khoảng trắng hoặc sai ký tự không. Sau khi sửa, chạy lại:

```bash
docker compose up -d --force-recreate
```

**Tắt Docker xong bị mất mạng:**

Do mục SOCKS Proxy trên macOS vẫn đang bật. Vào **System Settings → Network → Proxies** để tắt, hoặc chạy nhanh lệnh:

```bash
networksetup -setsocksfirewallproxystate Wi-Fi off
# hoặc (tắt trên mọi network service)
vpn-off
```

**Bật lại mất 1–2 phút mới vào được mạng (log có `You are already logged in - access denied`):**

Server VPN vẫn giữ phiên cũ do lần trước container bị tắt ngang (Quit Docker Desktop, Mac tắt nguồn/hết pin...). Khi dừng bằng `docker compose stop` / `vpn-off`, container tự ngắt phiên gọn gàng nên không gặp lỗi này. Nếu đã gặp: chờ 1–2 phút, container tự khởi động lại (`restart: unless-stopped`) và kết nối khi server hết hạn phiên cũ.

**`vpn-on` báo `Cannot detect the active network service`:**

Xem danh sách service rồi đặt thủ công:

```bash
networksetup -listallnetworkservices
export VPN_NET_SERVICE="Wi-Fi"
```
