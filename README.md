# L2TP/IPsec VPN Client for macOS (Docker)

Kết nối VPN L2TP/IPsec trên macOS thông qua Docker container, giải quyết triệt để vấn đề kẹt mạng hoặc không tương thích thuật toán mã hóa (3DES/SHA1) của macOS.

Bật bằng `vpn-on`: **toàn bộ máy** đi qua VPN — trình duyệt, DB client, SSH, Terminal, app... đều không cần cấu hình gì. Tắt bằng `vpn-off`: máy trở lại mạng bình thường.

```
Toàn bộ máy Mac ──WireGuard──▶ 127.0.0.1:51820/udp ──▶ [Docker: ppp0 (L2TP) → IPsec] ──▶ VPN Server
```

## Mục lục

1. [Yêu cầu chuẩn bị](#1-yêu-cầu-chuẩn-bị)
2. [Cài đặt (làm một lần)](#2-cài-đặt-làm-một-lần)
3. [Sử dụng hằng ngày](#3-sử-dụng-hằng-ngày)
4. [Chế độ chỉ một số ứng dụng (tùy chọn)](#4-chế-độ-chỉ-một-số-ứng-dụng-tùy-chọn)
5. [Tùy chỉnh](#5-tùy-chỉnh)
6. [Xử lý sự cố thường gặp](#6-xử-lý-sự-cố-thường-gặp)

## Cấu trúc dự án

| File                 | Vai trò                                                              |
| -------------------- | -------------------------------------------------------------------- |
| `Dockerfile`         | Image Alpine: strongSwan (IPsec), xl2tpd, ppp, WireGuard, microsocks |
| `entrypoint.sh`      | Sinh cấu hình IPsec/L2TP từ biến môi trường, dựng tunnel, chạy WireGuard + proxy |
| `docker-compose.yml` | Khai báo service, cổng WireGuard/proxy; nạp tài khoản từ `.env`      |
| `.env.example`       | Mẫu tài khoản VPN + port forward — copy thành `.env` (git bỏ qua `.env`) |
| `vpn.zsh`            | Phím tắt Terminal: `vpn-on`, `vpn-off`, `vpn-status`, `vpn-logs`, `vpn-exec` |
| `data/`              | Sinh tự động: khóa WireGuard + cấu hình cho Mac (git bỏ qua)         |

---

## 1. Yêu cầu chuẩn bị

- **Docker Desktop** đã cài và đang bật.
- **WireGuard** (dùng cho chế độ toàn máy):

  ```bash
  brew install wireguard-tools
  ```

  Trên Mac chip Intel đời cũ, Homebrew có thể phải tự biên dịch — mất 15–30 phút.
- Tài khoản VPN được cấp: địa chỉ server, PSK, username, password.

## 2. Cài đặt (làm một lần)

**Bước 1 — Tải mã nguồn** (khuyến nghị đặt tại `~/l2tp-proxy`):

```bash
git clone git@github.com:tms-thuannguyen1/proxy-vpn.git ~/l2tp-proxy
cd ~/l2tp-proxy
```

**Bước 2 — Điền tài khoản VPN** vào file `.env`:

```bash
cp .env.example .env
```

Mở `.env` và thay bằng thông tin bạn được cấp:

```bash
VPN_SERVER=your_vpn_server_ip      # IP hoặc Domain máy chủ VPN
VPN_PSK=your_preshared_key         # Khóa chia sẻ trước (Secret / PSK)
VPN_USER=your_vpn_username         # Tên tài khoản VPN
VPN_PASSWORD=your_vpn_password     # Mật khẩu VPN
```

> [!WARNING]
> Không commit file chứa tài khoản/mật khẩu cá nhân lên các kho mã nguồn công khai (public git). File `.env` đã được liệt kê trong `.gitignore` — đừng gỡ dòng đó và đừng dùng `git add -f .env`.

**Bước 3 — Cài phím tắt Terminal:** thêm dòng sau vào cuối `~/.zshrc` (sửa đường dẫn nếu bạn đặt dự án ở chỗ khác):

```bash
source ~/l2tp-proxy/vpn.zsh
```

Nạp lại cấu hình:

```bash
source ~/.zshrc
```

**Bước 4 — Build và chạy thử:**

```bash
docker compose up -d --build
```

Lần đầu build mất vài phút. Kiểm tra log:

```bash
docker logs l2tp-proxy | tail -20
```

Thấy đủ các dòng sau, không có dòng `ERROR:`, là kết nối VPN đã sẵn sàng:

1. `connection 'myvpn' established successfully` — IPsec xong
2. `CHAP authentication succeeded` — đăng nhập VPN xong
3. `VPN ppp0 đã nhận IP thành công!` — nhận IP nội bộ
4. `WireGuard bridge ready on udp/51820`

Nếu có lỗi, tra theo [mục 6](#6-xử-lý-sự-cố-thường-gặp).

## 3. Sử dụng hằng ngày

| Việc                            | Lệnh         |
| ------------------------------- | ------------ |
| Bật VPN cho toàn bộ máy         | `vpn-on`     |
| Tắt VPN, máy về mạng bình thường | `vpn-off`    |
| Xem trạng thái                  | `vpn-status` |
| Xem log container               | `vpn-logs`   |

Các lệnh này chạy được từ **bất kỳ thư mục nào** trong Terminal.

```bash
$ vpn-on
Starting VPN container...
Waiting for the VPN ....
Routing the whole Mac through the VPN (sudo password may be asked)...
VPN is ON for the whole Mac. Exit IP: xxx.xxx.xxx.xxx
```

- Mỗi lần bật mất khoảng **10–15 giây** (container kết nối lại IPsec + L2TP từ đầu).
- `vpn-on` hỏi **mật khẩu macOS** vì phải đổi route, DNS và IPv6 của hệ thống.
- `vpn-on` chỉ báo thành công khi đã kiểm tra IP ra Internet của máy **đúng bằng IP của VPN**. Nếu VPN không lên, nó **không** chuyển máy vào tunnel, nên máy không bị mất mạng.
- Mạng LAN tại chỗ (router, máy in, máy in mạng nội bộ) vẫn đi thẳng, không qua VPN.
- IPv6 tạm tắt trong lúc bật (VPN chỉ mang IPv4) để không có traffic đi vòng qua mạng thật; `vpn-off` bật lại.

> [!IMPORTANT]
> Luôn tắt bằng `vpn-off`. Nếu dừng container bằng `docker compose stop` hoặc Quit Docker Desktop trong khi VPN còn bật, máy sẽ **mất mạng** cho tới khi chạy `vpn-off`.

Đổi mạng (Wi-Fi ↔ Ethernet, sang quán cafe...) trong lúc đang bật: chạy `vpn-off` rồi `vpn-on` lại.

## 4. Chế độ chỉ một số ứng dụng (tùy chọn)

Dùng khi **không** muốn cả máy đi qua VPN (ví dụ muốn Zoom, YouTube vẫn dùng mạng cá nhân). Bật container ở chế độ này:

```bash
vpn-on --browser
```

Container mở **SOCKS5 proxy `127.0.0.1:1080`**, nhưng không đụng tới cài đặt mạng của máy. Chỉ ứng dụng nào được cấu hình mới đi qua VPN:

### a) Trình duyệt — dùng extension

1. Cài extension **ZeroOmega** (hoặc **Proxy SwitchyOmega**) trên Chrome / Brave / Edge.
2. Thêm profile mới:

   | Trường       | Giá trị      |
   | ------------ | ------------ |
   | Profile name | `Client VPN` |
   | Protocol     | `SOCKS5`     |
   | Server       | `127.0.0.1`  |
   | Port         | `1080`       |

3. Nhấn **Apply changes**. Khi cần dùng: chọn **Client VPN** trên thanh công cụ; khi nghỉ: chọn **[Direct]**.

### b) Database client / ứng dụng không hỗ trợ proxy — Port forwarding

Container mở sẵn cổng trên máy bạn, chuyển thẳng tới service qua VPN. Ứng dụng chỉ cần kết nối tới `127.0.0.1:<cổng>`.

1. Thêm vào `.env` (nhiều service ngăn cách bằng dấu phẩy, định dạng `cổng_local:host:cổng_đích`):

   ```bash
   PORT_FORWARDS=41000:mydb.xxxx.ap-northeast-1.rds.amazonaws.com:3306,41001:10.0.0.5:22
   ```

   Cổng local phải nằm trong dải `41000-41009`. Cần dải khác thì đặt thêm `FORWARD_PORTS=42000-42019` trong `.env`.

2. Áp dụng: `docker compose up -d`. Log sẽ in `Forwarding 127.0.0.1:41000 -> ...`.
3. Trong DB client (TablePlus, DBeaver, DataGrip...): **Host** `127.0.0.1`, **Port** `41000`, user/password của DB như bình thường.

> [!NOTE]
> Nếu DB bật kiểm tra chứng chỉ SSL theo hostname (`verify-full` / `VERIFY_IDENTITY`), đổi sang chế độ `require` vì kết nối tới `127.0.0.1` sẽ không khớp tên trong chứng chỉ.

### c) Lệnh CLI hỗ trợ biến môi trường proxy (curl, git, wget...)

Thêm `vpn-exec` phía trước lệnh:

```bash
vpn-exec curl https://ipinfo.io/ip
vpn-exec git clone https://git.example.com/team/repo.git
```

### d) SSH

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
> Không nên dùng mục **SOCKS proxy** trong System Settings → Network → Proxies: chỉ trình duyệt tôn trọng cài đặt này, còn DB client, `ssh`, Terminal... vẫn đi bằng IP thật. Cần toàn máy thì dùng `vpn-on` ([mục 3](#3-sử-dụng-hằng-ngày)).

## 5. Tùy chỉnh

Đặt biến **trước** dòng `source` trong `~/.zshrc`:

```bash
export VPN_NET_SERVICE="Wi-Fi"      # Ép dùng 1 network service cố định (mặc định: tự dò)
export VPN_PROXY_TIMEOUT=60         # Thời gian tối đa chờ VPN, giây (mặc định: 30)
export VPN_PROXY_PORT=1080          # Cổng SOCKS5 proxy (mặc định: 1080)
export VPN_PROXY_DIR=~/l2tp-proxy   # Thư mục dự án (mặc định: thư mục chứa vpn.zsh)
source ~/l2tp-proxy/vpn.zsh
```

Trong `.env`:

| Biến             | Ý nghĩa                                                                 |
| ---------------- | ----------------------------------------------------------------------- |
| `VPN_SERVER_ID`  | ID mà server VPN tự khai trong IPsec, nếu muốn kiểm tra chặt (mặc định: chấp nhận mọi ID) |
| `PORT_FORWARDS`  | Danh sách forward cổng — xem [mục 4b](#b-database-client--ứng-dụng-không-hỗ-trợ-proxy--port-forwarding) |
| `FORWARD_PORTS`  | Dải cổng dành cho forward (mặc định `41000-41009`)                      |

## 6. Xử lý sự cố thường gặp

**Xem log chi tiết của container:**

```bash
vpn-logs
# hoặc
docker logs -f l2tp-proxy
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

Container tự thử lại sau mỗi lần lỗi (`restart: unless-stopped`). Nếu lỗi do cấu hình, dừng hẳn bằng `vpn-off`, sửa `.env`, rồi `vpn-on`.

**Máy mất mạng hoàn toàn:**

VPN toàn máy vẫn bật trong khi container đã dừng (Quit Docker Desktop, `docker compose stop`...). Chạy:

```bash
vpn-off
```

Nếu Terminal chưa nạp phím tắt:

```bash
sudo wg-quick down ~/l2tp-proxy/data/wireguard/wg-l2tp.conf
sudo route -n delete -host "$(cat ~/l2tp-proxy/data/wireguard/vpn-server-ip)"
sudo networksetup -setv6automatic Wi-Fi
networksetup -setsocksfirewallproxystate Wi-Fi off
```

**`vpn-on` báo `VPN not ready after 30s`:**

VPN chưa kết nối được. Xem `vpn-logs` và tra bảng trên. Nếu mạng chậm, tăng thời gian chờ: `VPN_PROXY_TIMEOUT=60 vpn-on`.

**`vpn-on` báo `Tunnel is up but the Mac exits via ...`:**

Tunnel đã bật nhưng traffic chưa đi đúng đường. Chạy `vpn-off`, kiểm tra `vpn-status`, rồi thử lại. Thường do đổi mạng trong lúc đang bật.

**Bật lại mất 1–2 phút mới vào được mạng (log có `You are already logged in - access denied`):**

Server VPN vẫn giữ phiên cũ do lần trước container bị tắt ngang (Quit Docker Desktop, Mac tắt nguồn/hết pin...). Khi tắt bằng `vpn-off`, container tự ngắt phiên gọn gàng nên không gặp lỗi này. Nếu đã gặp: chờ 1–2 phút, container tự khởi động lại và kết nối khi server hết hạn phiên cũ.

**Đổi được IP nhưng ứng dụng vẫn không vào được service (khi dùng `vpn-on --browser`):**

Ứng dụng đó không đi qua SOCKS proxy nên vẫn dùng IP thật. Dùng `vpn-on` (toàn máy), hoặc port forwarding / `vpn-exec` theo [mục 4](#4-chế-độ-chỉ-một-số-ứng-dụng-tùy-chọn).

**`vpn-on` báo `Cannot detect the active network service`:**

Xem danh sách service rồi đặt thủ công:

```bash
networksetup -listallnetworkservices
export VPN_NET_SERVICE="Wi-Fi"
```

**`wg-quick not found`:**

Chưa cài WireGuard: `brew install wireguard-tools` ([mục 1](#1-yêu-cầu-chuẩn-bị)).
