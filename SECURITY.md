# Đánh giá bảo mật

Phạm vi: container Docker (IPsec/L2TP/WireGuard/SOCKS), phím tắt `vpn.zsh`, các gói cài thêm trên máy, và rủi ro khi kết nối từ mạng công ty có IP tĩnh.

Mọi kết luận dưới đây đều lấy từ kiểm tra thực tế trên máy đang chạy, không phải suy đoán. Lệnh tái hiện nằm ở [cuối file](#cách-tự-kiểm-tra-lại).

## Kết luận ngắn

- **Mạng công ty không bị lộ ra phía khách hàng.** Không có đường nào từ VPN khách hàng đi ngược vào LAN công ty: macOS không bật chuyển tiếp gói tin, container không có route tới LAN sau khi VPN lên, và chiều vào từ VPN đã bị chặn ở tường lửa container.
- **Đã tìm và vá 4 điểm yếu** (chi tiết bên dưới), trong đó nghiêm trọng nhất là proxy SOCKS mở không mật khẩu về phía mạng khách hàng.
- **Chế độ toàn máy là lựa chọn có chủ đích**: kết nối này phục vụ làm dự án cho khách hàng, nên việc traffic đi qua hạ tầng của họ là đúng mục đích. Điều cần nhớ là **tắt bằng `vpn-off` khi không làm việc**, để việc riêng không đi qua đó.

## Các điểm yếu đã tìm thấy và đã vá

### 1. Proxy SOCKS mở, không mật khẩu, lộ ra mạng VPN của khách hàng (Nghiêm trọng)

`microsocks` chạy **không có xác thực** và lắng nghe trên mọi interface, gồm cả `ppp0` — tức địa chỉ của máy bạn **bên trong mạng VPN khách hàng**:

```
tcp  0  0 0.0.0.0:1080  0.0.0.0:*  LISTEN  85/microsocks
ppp0  UNKNOWN  10.200.0.23 peer 10.200.110.1/32
```

Bất kỳ máy nào trong mạng VPN đó chạm được `10.200.0.23:1080` đều có thể mượn kết nối của bạn để đi ra Internet (log phía dịch vụ sẽ thấy IP VPN của bạn), hoặc quét các máy khác trong cùng mạng VPN qua proxy này. Mức độ khai thác thực tế phụ thuộc việc server VPN có cách ly máy khách với nhau không — điều này nằm ở phía khách hàng, ta không kiểm soát được.

**Đã vá:** proxy chỉ còn lắng nghe trên mạng nội bộ của Docker (`172.26.0.2:1080`); các cổng `PORT_FORWARDS` cũng vậy. Cổng công bố ra máy Mac vẫn chỉ ở `127.0.0.1`, máy khác trong LAN công ty không chạm được.

### 2. Container làm cầu nối cho phía VPN đi vào máy bạn (Cao)

Container bật chuyển tiếp gói tin (`ip_forward=1`) cho WireGuard, nhưng tường lửa để mặc định `ACCEPT` mọi chiều. Máy bên phía VPN có thể gửi gói tin tới `10.99.0.2` để chạm thẳng vào máy Mac qua đường WireGuard, hoặc dùng container làm bộ định tuyến sang mạng nội bộ Docker.

**Đã vá:** chặn mọi kết nối chủ động đi vào từ `ppp0`, chỉ cho phép gói tin trả lời cho kết nối do mình mở trước:

```
-A INPUT   -i ppp0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A INPUT   -i ppp0 -j DROP
-A FORWARD -i ppp0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A FORWARD -i ppp0 -j DROP
```

### 3. Container chạy quyền cao nhất (`privileged: true`) (Trung bình)

`privileged` cho container gần như toàn quyền với nhân của máy ảo Docker: mọi capability, truy cập mọi thiết bị, ghi được `/proc/sys`. Nếu một tiến trình trong container bị chiếm quyền (strongSwan, pppd, microsocks đều tiếp xúc trực tiếp với mạng), thiệt hại sẽ lan rộng.

**Đã vá:** bỏ `privileged`, thay bằng quyền tối thiểu — đã kiểm chứng IPsec, L2TP, WireGuard, iptables đều chạy bình thường:

```yaml
cap_add: [NET_ADMIN]          # chỉ 1 capability thay vì toàn bộ
devices: [/dev/ppp]           # chỉ 1 thiết bị
sysctls: [net.ipv4.ip_forward=1]
security_opt: [no-new-privileges:true]
```

### 4. Nguồn cài đặt không cố định phiên bản (Trung bình)

`FROM alpine:latest` và `git clone` nhánh mặc định của `microsocks` nghĩa là mỗi lần build có thể ra nội dung khác nhau, và nếu upstream bị chiếm quyền thì mã độc vào thẳng image.

**Đã vá:** cố định `alpine:3.24` và `microsocks` theo tag phát hành `v1.0.5`.

## Rủi ro còn lại (cần biết, không vá được bằng code)

### a) Trong lúc bật, khách hàng thấy được traffic của máy

Đây là hệ quả tất yếu của việc đẩy toàn bộ máy qua VPN, và là **điều mong muốn** trong bối cảnh dùng để làm dự án cho khách hàng. Ghi lại để mọi người trong nhóm biết rõ phạm vi:

- Phía VPN thấy: bạn truy cập tên miền nào, lúc nào, lưu lượng bao nhiêu, và toàn bộ truy vấn DNS.
- Phía VPN **không** đọc được nội dung của các kết nối HTTPS/TLS.
- Trong lúc bật, traffic không liên quan tới khách hàng (Slack nội bộ công ty, dự án của khách hàng khác, việc riêng) cũng đi qua đó.

**Cách làm đúng:** bật `vpn-on` khi bắt đầu làm việc với khách hàng, `vpn-off` khi xong. Không để bật qua đêm hay lúc dùng máy cho việc riêng. Nếu cần vừa làm dự án vừa giữ phần còn lại trong mạng công ty, dùng `vpn-on --browser` kèm port forwarding cho DB.

### b) Đường hầm VPN dùng thuật toán yếu

Server khách hàng chọn `3DES_CBC/HMAC_SHA1/MODP_1024` cho cả IKE lẫn ESP. Đây là bộ thuật toán đã lỗi thời (3DES, SHA-1, khoá DH 1024-bit). Cấu hình của ta ưu tiên AES-256/SHA-256/MODP-2048 trước, nhưng server chỉ hỗ trợ đến vậy.

**Hệ quả:** đừng coi đường hầm này là lớp bảo vệ đủ mạnh cho dữ liệu nhạy cảm — hãy dựa vào HTTPS/TLS ở bên trên. Nếu quan hệ công việc cho phép, đề nghị khách hàng nâng cấu hình server.

### c) Tài khoản VPN nằm dạng chữ thường trên máy

`.env` (quyền `600`) và biến môi trường của container. Bất kỳ ai dùng được tài khoản macOS của bạn, hoặc chạy được `docker inspect l2tp-proxy`, đều đọc được mật khẩu VPN. Khoá WireGuard trong `data/` cũng vậy (quyền `600`).

**Khuyến nghị:** bật FileVault, khoá máy khi rời chỗ, không dùng chung tài khoản macOS. Không bao giờ commit `.env` hay `data/` (đã có trong `.gitignore`, và lịch sử git hiện **sạch** — đã kiểm tra).

### d) IPv6 bị tắt trong lúc bật VPN

Đây là chủ ý, để traffic không đi vòng ra ngoài đường hầm. `vpn-off` bật lại. Nhưng nếu máy sập nguồn khi đang bật VPN, IPv6 sẽ vẫn tắt sau khi khởi động lại — chạy `vpn-off` hoặc `sudo networksetup -setv6automatic Wi-Fi` để khôi phục.

### e) Các gói cài thêm trên máy

`brew install wireguard-tools` kéo theo `wireguard-go` và `bash` (bản Homebrew). Đều là công thức chính thức của Homebrew, mã nguồn mở, do tác giả WireGuard phát hành. `wg-quick` cần `sudo` vì phải đổi route/DNS — đây là bản chất của mọi VPN client, không riêng gì cách làm này.

## Về câu hỏi: dùng IP tĩnh của mạng công ty có ảnh hưởng gì không

Đã kiểm tra từng hướng:

| Hướng | Kết quả | Bằng chứng |
| --- | --- | --- |
| Khách hàng nhìn ngược vào **LAN công ty** | **Không thể** | macOS không chuyển tiếp gói tin (`net.inet.ip.forwarding: 0`); sau khi VPN lên, container không còn route tới `10.20.200.0/23`; chiều vào từ `ppp0` đã bị chặn |
| Khách hàng chạm vào **máy Mac của bạn** | **Không thể** (sau khi vá) | Trước khi vá thì chạm được qua `10.99.0.2`; nay `FORWARD -i ppp0 DROP` |
| Máy khác trong **LAN công ty** dùng ké proxy | **Không thể** | Cổng chỉ mở ở `127.0.0.1`; thử kết nối từ IP LAN của máy: `Connection refused` |
| Khách hàng biết **IP tĩnh công ty** | **Có** — không tránh được | Mọi VPN đều lộ IP nguồn của client. Đây là thông tin gắn với cả công ty, không riêng máy bạn |
| Dịch vụ bên ngoài thấy IP nào | **IP của VPN khách hàng**, không phải IP công ty | Đúng mục đích sử dụng |

Điểm cần cân nhắc duy nhất về mặt tổ chức: vì IP công ty là tĩnh, phía khách hàng có nhật ký gắn chính xác công ty bạn với từng phiên kết nối, gồm thời điểm và thời lượng. Đây là chuyện bình thường trong hợp đồng, nhưng nên xác nhận nội bộ rằng việc dùng kết nối này từ mạng công ty là được phép.

## Khuyến nghị vận hành

1. Bật `vpn-on` khi bắt đầu làm việc với khách hàng, `vpn-off` khi xong. Tránh để bật lúc dùng máy cho việc riêng.
2. Mỗi người **một tài khoản VPN riêng**. Dùng chung tài khoản vừa gây lỗi `You are already logged in`, vừa làm nhật ký phía khách hàng không phân biệt được ai.
3. Không commit `.env`, `data/`. Khi nghỉ dự án, đề nghị khách hàng thu hồi tài khoản VPN.
4. Định kỳ chạy `docker compose build --pull` để lấy bản vá bảo mật của Alpine; nâng phiên bản ghim trong `Dockerfile` khi có bản mới.
5. Bật FileVault trên máy.

## Cách tự kiểm tra lại

```bash
cd ~/l2tp-proxy

# Cổng nào đang mở, ở địa chỉ nào (phải là 172.x của Docker, KHÔNG phải 0.0.0.0)
docker exec l2tp-proxy netstat -lntp

# Tường lửa: phải thấy 4 dòng ppp0
docker exec l2tp-proxy iptables -S | grep ppp0

# Quyền container: privileged phải là false
docker inspect -f 'privileged={{.HostConfig.Privileged}} caps={{.HostConfig.CapAdd}}' l2tp-proxy

# Cổng trên Mac: chỉ được mở ở 127.0.0.1
lsof -nP -iTCP:1080 -sTCP:LISTEN

# Máy Mac không được làm router
sysctl net.inet.ip.forwarding

# Quyền file nhạy cảm: phải là -rw-------
ls -l .env data/wireguard/

# Git không được chứa file nhạy cảm
git ls-files
```
