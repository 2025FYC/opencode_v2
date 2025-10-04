import jwt
import datetime

secret = "pR4wE_f5o2lVX97Qh1L3z8DgHYmKu6aC0wBJqxn2S9tFzM1kN4vU7rGpOeZiAbEd"

payload = {
    "userId": "test-user-123",
    "username": "testuser",
    "email": "test@example.com",
    "iat": datetime.datetime.utcnow(),
    "exp": datetime.datetime.utcnow() + datetime.timedelta(days=7)
}

token = jwt.encode(payload, secret, algorithm="HS256")
print(f"JWT Token: {token}")