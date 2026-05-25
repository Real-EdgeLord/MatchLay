**🎮 MatchLay Godot Plugin**  
   
 [![](data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAE4AAAAUCAYAAAAjvwuMAAAABmJLR0QA/wD/AP+gvaeTAAAACXBIWXMAAA7EAAAOxAGVKw4bAAAFWUlEQVR4nO2Yb2gTZxzHP/cn8S5JGy22UMiYQqvlnCZpaNAhTNRaYUxmMZtsagdzGwxWZJVKcQzcBr4Y87Vje1EYglXf6F6lGZaKRI32hU6mDldwSpOosa39d83l7vaiTbVt1FYZtdAvHHfP937P8/x+37vf89z9hEgk4lBV9SegASi2bZupmMrNtv1/jfF7xWfYkw3GTs9qj3PPbU/lJo0hPEYQWnEv2S+Pi/bVNC8XUAB2MbbdyFAvImNv2gJmA9tqEIHiufZj3sG2veJc+zBfsSDcS+KZwj169GhiF3v6egFjKCicoijcv3+fRYsWUVZWRldX17wRTpaESW3pqQjF8VuyKEw7ZouCwpWXl7Nz5048Hg8+n4/a2lpEcbKpYRhYljWtr2EYz5wsl8sV7JPL5cjlcgX52cBfXkTfoc2EfGP7nc+7iN7vanlPK8VfXsTPO97CIQr8smMVv0ZW0fPtxrHrHatQHbNbteRCpGmaWJaFYRgMDAzQ0dHBgQMHCAQCpFIpmpubcTgcbN26lW3btpHJZGhtbWVgYIDq6mqCwSBer5czZ87gdDoJh8P4fD6i0ShtbW1UVlZSX1+P3+/nypUrHD16FMuykCSJ6upqMpkMt27dwuFwYBgGVVVVLFmy5IXB2Jl/iXXofLyihK57j/lI8xI72wE9aaxhEbtnhFHDoOHTzxEEgSu//UjD3iYQBHhnL4JTfTXh8igpKUHTNMLhMKtXr+bw4cPcvXsXv99PTU0NoVCII0eOUFdXRzAYBGDXrl00NTXh9/tZv349qqrS3t7OzZs30TSNUCiEoiisXLmSlpYWNmzYQEtLC+3t7RMP68aNGxN2Q0NDXL16lXXr1r1YOODuo0HKShQUh0jNUoFE1x1AmbARJRm7rhEBQJIRtzRO/3N4VeEsy8I0TdauXUssFsMwDLLZLB6Ph8rKShYvXsy+ffsYHR1FFEWuX7/OuXPn6O3t5dq1awQCAeLxOLt378a2baLRKLquEwgE8Hq9HDx4kP7+fgYHB0mlUpSWltLX14coiqTT6Qk/crkcuq6jKMpzvM1H5OT0H518/+4HXEycRS4qgWH9JaR5wTQzMUomk1RVVZFIJJAkCYAHDx6QTqeJRqM8fPiQnp4e6uvrcTgcFBcXs2zZMgRBIJlMEolE2L59O83NzRw6dIhUKsWlS5eIRqMYhkF/fz9DQ0N0d3ezfPlyZFnG7XZPzK9pGg6HY0YB2cDpf4b4uhTev3CTT7a8PXtVZoBnCpffRW3b5uTJk5w6dYoVK1aQyWQ4ceIEnZ2dNDY2smbNGgRB4NixY6iqiqIoLF26FLfbjSiK1NbWEolE8Pl8JBIJANra2jh+/Dh+vx9Zlrl8+TIXL17k/PnzqKqKruu43W5UdWzNMQwDWZZntrPboL9ZQ827H05PwyndX+VLQdizZ8+UYoFNNpslFouxadMmRkdHicfjhEIhVFUlmUxy7949PB4Pg4ODVFRU4PF46Ovro7u7G0VRkCQJ0zTRNA1ZlonH44TDYQCKioqIxWIEg0GGh4e5c+cOiqJgmiYejwdN00in09y+fRuXy4VpmgCEQqEXVkes5N9Yf51F2vhFPhjMC8eh5A3wlmH/2Y60+Uvy9Q7r5DeIO36YRXXkCVdQuOnjPHn7BEHANE10XcfpdCJJ0gRv2zYjIyNIkoTT6ZzUP28zlTNNk2w2iyzLk9LRsix0XZ801tyXlZ5wM1rj8sgHLooiLper4H2XyzUtwKcFm8rLslwwDQVBmEjV1xEi8HiunZh3EIR+EWidaz/mGWwEsVUeGRnZP54SDYB3jp16zSH050vn/wEw7HGlR5IZMwAAAABJRU5ErkJggg==)  
   
 ](LICENSE "LICENSE")[![](data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAABmJLR0QA/wD/AP+gvaeTAAAACXBIWXMAAA7EAAAOxAGVKw4bAAAADUlEQVR4nGP4//8/AwAI/AL+p5qgoAAAAABJRU5ErkJggg==)  
](https://github.com/Real-EdgeLord/MatchLay "https://github.com/Real-EdgeLord/MatchLay")  
This plugin provides a **GDScript client** for the MatchLay matchmaker. It handles room creation, joining, player counts, and heartbeats – but  **it does NOT handle the actual game connection**. For that, you need a UDP relay like [Noray. Think of MatchLay as the *directory* and Noray as the  *bridge* that moves packets between players.](https://github.com/foxssake/noray "https://github.com/foxssake/noray")  
![](data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAnEAAAACCAYAAAA3pIp+AAAABmJLR0QA/wD/AP+gvaeTAAAACXBIWXMAAA7EAAAOxAGVKw4bAAAANUlEQVR4nO3OMQ2AABAAsSPBCUZfE2IYmVDBhAU2QtIq6DIzW7UHAMBfnGt1V8fXEwAAXrse/xcF7U7sx4wAAAAASUVORK5CYII=)  
**📦 Installation**  
1. Copy the matchlay folder into your Godot project's addons/ directory.  
2. Enable the plugin in **Project → Project Settings → Plugins**.  
3. The MatchLayAPI class will be globally available.  
![](data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAnEAAAACCAYAAAA3pIp+AAAABmJLR0QA/wD/AP+gvaeTAAAACXBIWXMAAA7EAAAOxAGVKw4bAAAANElEQVR4nO3OMQ0AIAwAwZIgBKn1gjJsdGLBABMhuZt+/JaZIyJmAADwi9VP1NMNAABu1AaU4gUeBSGW2wAAAABJRU5ErkJggg==)  
**🚀 Quick Start**  
**1. Initialize the API**  
var api = MatchLayAPI.new()  
 add_child(api)  
 api.init("http://your-matchmaker-server:8000", "your-secret-key")  
   
your-secret-key must match the SECRET_KEY environment variable of your MatchLay server.  
1. Host a Game (Game Server)  
gdscript  
api.room_hosted.connect(_on_room_hosted)# server_oid: the Noray OID of your game server (obtained from Noray)api.host_game(server_oid, 300, {"map": "arena", "mode": "dm"})func _on_room_hosted(room_id: String, secret: String, host_key: String):    print("Room created! Share this secret with players: ", secret)    # The host_key is stored internally – you don't need to use it directly.    # The plugin automatically adds the host as the first player.  
2. Join a Game (Player Client)  
gdscript  
api.room_joined.connect(_on_room_joined)# The secret is entered by the player (6 uppercase letters)api.join_with_secret("ABCDEF")func _on_room_joined(room_id: String, server_oid: String, player_count: int):    print("Joined room ", room_id, " | server OID: ", server_oid)    # Now connect your Noray client to the server_oid and the Noray host/port    # (those are configured on the Noray server, not in MatchLay)  
3. Handle Errors & Expiry  
gdscript  
api.error_occurred.connect(_on_error)api.room_expired.connect(_on_room_expired)func _on_error(code: int, message: String):    print("MatchLay error: ", code, " - ", message)func _on_room_expired(room_id: String):    print("Room ", room_id, " expired or was closed")    # Clean up local game state  
## **Signals (Full List)**  
| | | |  
|-|-|-|  
| **Signal** | **Arguments** | **Description** |   
| rooms_listed | rooms: Array | Response to list_rooms(). Each room contains room_id, public_data, player_count, match_time. |   
| room_hosted | room_id: String, secret: String, host_key: String | Successful room creation. The host key is stored internally; you only need the secret to share with players. |   
| room_joined | room_id: String, server_oid: String, player_count: int | Successful join. Use server_oid to connect via Noray. |   
| player_count_updated | room_id: String, player_count: int | Sent after add_player() or remove_player(). |   
| heartbeat_ok | – | Heartbeat successfully sent (host only). |   
| room_closed | – | Room successfully closed via close_room(). |   
| error_occurred | code: int, message: String | Any HTTP or API error. |   
| room_expired | room_id: String | The matchmaker deleted the room (no heartbeat or zero players). |   
| server_down | – | The matchmaker server is unreachable (health check failed). |   
## **API Methods**  
| | | |  
|-|-|-|  
| **Method** | **Arguments** | **Description** |   
| init(url, key) | url: String, key: String | Sets the matchmaker URL and global API key. Must be called first. |   
| host_game(server_oid, match_time, public_data) | server_oid: String, match_time: int, public_data: Dictionary | Creates a new room. Heartbeat starts automatically. |   
| join_with_secret(secret) | secret: String | Joins a room using the 6‑letter secret. |   
| join_with_room_id(room_id) | room_id: String | Joins a room using the short room ID (less secure). |   
| list_rooms() | – | Fetches all active rooms; emits rooms_listed. |   
| add_player(player_oid) | player_oid: String | Host only. Adds a player to the room. |   
| remove_player(player_oid) | player_oid: String | Host only. Removes a player from the room. |   
| close_room() | – | Host only. Closes the room permanently. |   
| leave_room() | – | Cleans local state (does not call the server). |   
## **The Big Picture: MatchLay + Noray**  
MatchLay **does not move game packets** – it only helps players discover each other. The actual UDP relay is handled by Noray (or any other solution). Here's how they work together:  
4. Game server starts and registers itself with Noray, obtaining a server_oid.  
5. Game server calls host_game(server_oid, ...) on MatchLay. MatchLay returns a secret.  
6. Player receives the secret (e.g., from a chat message).  
7. Player calls join_with_secret(secret). MatchLay returns the server_oid.  
8. Player connects to Noray using the server_oid (and the public Noray host/port, which is known from your Noray deployment). From that point on, **MatchLay is not involved** – all game traffic flows via Noray.  
This separation keeps the matchmaker simple and allows you to use any UDP relay (or even direct IP connections).  
## **⚠️ Disclaimer**  
This software is provided “as is”, without warranty of any kind, express or implied. The authors are not responsible for any loss of data, network failures, or unexpected disconnections. You are responsible for securing your own deployment (HTTPS, firewall, etc.). MatchLay is intended for self‑hosted and educational use.  
## **Certified AI Slop**  
“This README was written by an AI that has never hosted a lobby and thinks UDP stands for ‘Unbelievably Dumb Packets’. If something breaks, please blame the AI – but fix it yourself.”  
Yes, this documentation was generated by a large language model. The code is human‑written (mostly), but the friendly tone and reassuring bullet points are pure vectorized cognition. Use it, share it, and remember: the real latency was the friends we met along the way. 🎲  
[https://img.shields.io/badge/Built%2520with-Certified%2520AI%2520Slop-ff69b4?style=flat-square](https://img.shields.io/badge/Built%2520with-Certified%2520AI%2520Slop-ff69b4?style=flat-square "https://img.shields.io/badge/Built%2520with-Certified%2520AI%2520Slop-ff69b4?style=flat-square")  
Made with ❤️ and ☕ for the Godot community.  
   
