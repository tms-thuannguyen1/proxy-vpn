# L2TP/IPsec VPN Client for macOS (Docker)

Giải pháp kết nối VPN L2TP/IPsec ổn định trên macOS thông qua Docker container, giải quyết triệt để vấn đề kẹt mạng hoặc không tương thích thuật toán mã hóa (3DES/SHA1) của macOS. Có 2 chế độ:

- **Toàn bộ máy Mac** (`vpn-on`): mọi ứng dụng — trình duyệt, DB client, SSH, Terminal, Slack... — đều đi qua VPN, giống như VPN có sẵn của macOS.
- **Chỉ ứng dụng chọn lọc** (`vpn-on --browser`): chỉ trình duyệt/ứng dụng được cấu hình dùng **SOCKS5 Proxy `127.0.0.1:1080`** mới đi qua VPN; phần còn lại dùng mạng bình thường.

```
Toàn bộ máy Mac ──WireGuard──▶ 127.0.0.1:51820/udp ─┐
                                                   ├─▶ [Docker: ppp0 (L2TP) → IPsec] ──▶ VPN Server
Trình duyệt / app ──SOCKS5──▶ 127.0.0.1:1080 ───────┘
```

## Mục lục

1. [Yêu cầu chuẩn bị](#1-yêu-cầu-chuẩn-bị)
2. [Cấu hình thông tin tài khoản](#2-cấu-hình-thông-tin-tài-khoản)
3. [Khởi chạy lần đầu](#3-khởi-chạy-lần-đầu)
4. [Cách sử dụng](#4-cách-sử-dụng)
5. [Bật / Tắt hàng ngày](#5-bật--tắt-hàng-ngày)
6. [Phím tắt Terminal (zsh)](#6-phím-tắt-terminal-zsh)
7. [Xử lý sự cố thường gặp](#7-xử-lý-sự-cố-thường-gặp)

## Cấu trúc dự án

| File                 | Vai trò                                                              |
| -------------------- | -------------------------------------------------------------------- |
| `Dockerfile`         | Image Alpine: strongSwan (IPsec), xl2tpd, ppp, WireGuard, microsocks |
| `entrypoint.sh`      | Sinh cấu hình IPsec/L2TP từ biến môi trường, dựng tunnel, chạy proxy và cầu nối WireGuard |
| `docker-compose.yml` | Khai báo service, cổng proxy/WireGuard; nạp tài khoản từ `.env`      |
| `.env.example`       | Mẫu tài khoản VPN + port forward — copy thành `.env` (git bỏ qua `.env`) |
| `vpn.zsh`            | Phím tắt Terminal: `vpn-on`, `vpn-off`, `vpn-status`, `vpn-logs`, `vpn-exec` |
| `data/`              | Sinh tự động: khóa WireGuard + cấu hình cho Mac (git bỏ qua)         |
| `TESTING.md`         | Kịch bản test lại toàn bộ từ đầu, có kết quả mong đợi từng bước      |

---

## 1. Yêu cầu chuẩn bị

- Máy đã cài đặt và đang bật **Docker Desktop**.
- Đã clone hoặc tải thư mục mã nguồn này về máy (khuyến nghị đặt tại `~/l2tp-proxy`).
- Chế độ **toàn bộ máy Mac** cần thêm WireGuard (một lần):

  ```bash
  brew install wireguard-tools
  ```

  Trên Mac chip Intel đời cũ, Homebrew có thể phải tự biên dịch — mất 15–30 phút.

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

## 4. Cách sử dụng

Chọn cách phù hợp với nhu cầu.

### Cách 1: Toàn bộ máy Mac (Khuyên dùng khi cần truy cập mọi thứ)

Mọi traffic của máy (web, DB, SSH, API, Slack, Zoom...) đi qua VPN — ứng dụng **không cần cấu hình gì**. Mạng LAN tại chỗ (router, máy in) vẫn dùng bình thường.

1. Cài phím tắt theo [mục 6](#6-phím-tắt-terminal-zsh) và `wireguard-tools` theo [mục 1](#1-yêu-cầu-chuẩn-bị).
2. Bật: `vpn-on` (nhập mật khẩu macOS khi được hỏi). Lệnh chỉ báo thành công khi đã kiểm tra IP ra Internet của máy **đúng bằng IP của VPN**.
3. Tắt: `vpn-off`.

Cách hoạt động: container dựng thêm một WireGuard server; `vpn-on` dùng `wg-quick` tạo card mạng ảo trên Mac, chuyển toàn bộ route + DNS vào đó; container NAT traffic ra `ppp0` của VPN.

> [!NOTE]
> - Trong lúc bật, IPv6 của mạng đang dùng tạm tắt (VPN chỉ mang IPv4) để không có traffic đi vòng qua mạng thật; `vpn-off` bật lại.
> - Nếu đổi mạng (Wi-Fi ↔ Ethernet, sang quán cafe...) trong lúc đang bật: chạy `vpn-off` rồi `vpn-on` lại.

### Cách 2: Chỉ dùng cho Trình duyệt

Không ảnh hưởng đến mạng chung của máy (Zoom, Meet, YouTube, Slack vẫn dùng mạng cá nhân bình thường). Bật container bằng `vpn-on --browser` (hoặc `docker compose up -d`).

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

### Cách 3: Chỉ một số ứng dụng / lệnh Terminal

Dùng khi muốn **một vài** công cụ đi qua VPN mà không bật toàn máy (Cách 1). Bật container bằng `vpn-on --browser`.

**a) Database client / ứng dụng bất kỳ — Port forwarding**

Container mở sẵn cổng trên máy bạn, chuyển thẳng tới service qua VPN. Ứng dụng **không cần hỗ trợ proxy**, chỉ cần kết nối tới `127.0.0.1:<cổng>`.

1. Thêm vào `.env` (nhiều service ngăn cách bằng dấu phẩy, định dạng `cổng_local:host:cổng_đích`):

   ```bash
   PORT_FORWARDS=41000:mydb.xxxx.ap-northeast-1.rds.amazonaws.com:3306,41001:10.0.0.5:22
   ```

   Cổng local phải nằm trong dải `41000-41009`. Cần dải khác thì đặt thêm `FORWARD_PORTS=42000-42019` trong `.env`.

2. Áp dụng: `docker compose up -d`. Log sẽ in `Forwarding 127.0.0.1:41000 -> ...`.
3. Trong DB client (TablePlus, DBeaver, DataGrip...): **Host** `127.0.0.1`, **Port** `41000`, user/password của DB như bình thường.

> [!NOTE]
> Nếu DB bật kiểm tra chứng chỉ SSL theo hostname (`verify-full` / `VERIFY_IDENTITY`), đổi sang chế độ `require` vì kết nối tới `127.0.0.1` sẽ không khớp tên trong chứng chỉ.

**b) Lệnh CLI hỗ trợ biến môi trường proxy (curl, git, wget...)** — thêm `vpn-exec` phía trước lệnh:

```bash
vpn-exec curl https://ipinfo.io/ip
vpn-exec git clone https://git.example.com/team/repo.git
```

**c) SSH** — đi qua SOCKS proxy bằng `ProxyCommand`:

```bash
ssh -o ProxyCommand='nc -X 5 -x 127.0.0.1:1080 %h %p' user@server
```

Hoặc cố định trong `~/.ssh/config` (áp dụng cho cả SSH tunnel của DB client):

```
Host my-bastion
  HostName bastion.example.com
  User ec2-user
  ProxyCommand nc -X 5 -x 127.0.0.1:1080 %h %p
```

> [!WARNING]
> Không nên dùng mục **SOCKS proxy** trong System Settings → Network → Proxies: chỉ trình duyệt tôn trọng cài đặt này, còn DB client, `ssh`, Terminal... vẫn đi bằng IP thật. Cần toàn máy thì dùng **Cách 1**.

## 5. Bật / Tắt hàng ngày

Dùng phím tắt ở [mục 6](#6-phím-tắt-terminal-zsh):

| Việc                               | Lệnh               |
| ---------------------------------- | ------------------ |
| Bật VPN cho toàn bộ máy (Cách 1)   | `vpn-on`           |
| Bật VPN cho trình duyệt/app (Cách 2, 3) | `vpn-on --browser` |
| Tắt VPN                            | `vpn-off`          |

Mỗi lần bật mất khoảng **10–15 giây** (container kết nối lại IPsec + L2TP từ đầu).

> [!IMPORTANT]
> Luôn tắt bằng `vpn-off` khi đang dùng Cách 1. Nếu dừng container bằng `docker compose stop` hoặc Quit Docker Desktop trong lúc tunnel còn bật, máy sẽ **mất mạng** cho tới khi chạy `vpn-off`.

Không dùng phím tắt thì bật/tắt container trực tiếp (chỉ cho Cách 2, 3):

```bash
docker compose start   # bật
docker compose stop    # tắt
```

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
| `vpn-on`           | Bật container, **chờ đến khi VPN thực sự thông**, rồi chuyển toàn bộ máy qua VPN (Cách 1)   |
| `vpn-on --browser` | Chỉ bật container, không đụng cài đặt mạng macOS (Cách 2, 3)                                |
| `vpn-off`          | Gỡ tunnel toàn máy (khôi phục route, DNS, IPv6), rồi dừng container                         |
| `vpn-status`       | Xem trạng thái container, tunnel toàn máy, IP ra của VPN và của máy                         |
| `vpn-logs`         | Xem log container theo thời gian thực                                                       |
| `vpn-exec <lệnh>`  | Chạy lệnh CLI qua VPN (curl, git, wget...) — xem [Cách 3](#cách-3-chỉ-một-số-ứng-dụng--lệnh-terminal)   |

### Điểm cải tiến so với script đơn giản

- **Không `cd`**: gọi `docker compose -f <dir>/docker-compose.yml`, Terminal vẫn giữ nguyên thư mục hiện tại.
- **Tự dò network service đang dùng** (Wi-Fi / Ethernet / USB LAN...) theo default route, không hardcode `Wi-Fi`.
- **Chờ VPN sẵn sàng thật** (thử `curl` qua proxy mỗi giây, tối đa 30 giây) thay vì `sleep 3` cố định. Nếu VPN không lên, **không** chuyển máy vào tunnel → tránh mất mạng toàn máy.
- **Kiểm tra kết quả**: `vpn-on` chỉ báo thành công khi IP ra Internet của máy đúng bằng IP của VPN.
- **`vpn-off` hoàn tác đúng những gì `vpn-on` đã đổi** (route, DNS, IPv6), và tắt luôn SOCKS proxy thủ công nếu còn bật.
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
> `vpn-on` / `vpn-off` (Cách 1) hỏi mật khẩu macOS (`sudo`) vì thay đổi route, DNS và IPv6 của hệ thống.

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

**Đổi được IP nhưng ứng dụng (DB client, Terminal...) vẫn không vào được service:**

Ứng dụng đó không đi qua SOCKS proxy nên vẫn dùng IP thật. Dùng **Cách 1** (toàn bộ máy), hoặc port forwarding / `vpn-exec` theo [Cách 3](#cách-3-chỉ-một-số-ứng-dụng--lệnh-terminal).

**Máy mất mạng hoàn toàn:**

Tunnel toàn máy vẫn bật trong khi container đã dừng (Quit Docker Desktop, `docker compose stop`...), hoặc SOCKS proxy thủ công còn bật. Chạy:

```bash
vpn-off
```

Nếu chưa cài phím tắt: `sudo wg-quick down ~/l2tp-proxy/data/wireguard/wg-l2tp.conf` và `networksetup -setsocksfirewallproxystate Wi-Fi off`.

**Bật lại mất 1–2 phút mới vào được mạng (log có `You are already logged in - access denied`):**

Server VPN vẫn giữ phiên cũ do lần trước container bị tắt ngang (Quit Docker Desktop, Mac tắt nguồn/hết pin...). Khi dừng bằng `docker compose stop` / `vpn-off`, container tự ngắt phiên gọn gàng nên không gặp lỗi này. Nếu đã gặp: chờ 1–2 phút, container tự khởi động lại (`restart: unless-stopped`) và kết nối khi server hết hạn phiên cũ.

**`vpn-on` báo `Cannot detect the active network service`:**

Xem danh sách service rồi đặt thủ công:

```bash
networksetup -listallnetworkservices
export VPN_NET_SERVICE="Wi-Fi"
```
