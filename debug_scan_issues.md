# Debug Guide: Scan Completion and API Issues

## Issues Fixed:

### 1. **Scan Completion Flow Improved**
- ✅ Fixed `handleScanComplete` method to immediately notify Flutter
- ✅ Added proper error handling and logging with emojis for easier debugging
- ✅ Added immediate upload attempt when online
- ✅ Added `scanUploadComplete` method call to notify Flutter of upload results
- ✅ Better status management (pending, uploading, failed, completed)

### 2. **Flutter Dashboard Enhanced**
- ✅ Added `scanUploadComplete` handler to show upload success/failure messages
- ✅ Better user feedback for scan events (saved locally, uploaded, failed)
- ✅ Auto-refresh scan list after upload events

### 3. **API Authentication Issue Identified**
- ⚠️ Server is responding but returning 401 - authentication required
- 🔧 Need to check auth token storage and retrieval

## Testing Your Server:
Your Django server is running at `http://192.168.1.5:9000` but requires authentication.

Test API with auth token:
```bash
# Get your auth token first (from Flutter SharedPreferences or UserDefaults)
curl -H "Authorization: Token YOUR_TOKEN_HERE" http://192.168.1.5:9000/api/v1/scans/
```

## Next Steps to Debug:

### 1. Check Auth Token
Run this in Xcode console or check UserDefaults:
```swift
print("Auth token: \(UserDefaults.standard.string(forKey: "auth_token") ?? "NOT FOUND")")
print("Flutter auth token: \(UserDefaults.standard.string(forKey: "flutter.auth_token") ?? "NOT FOUND")")
```

### 2. Check Logs in Console
Look for these log messages during scan completion:
- `✅ [SCAN COMPLETE] Processing scan completion for:`
- `🚀 [SCAN COMPLETE] Attempting immediate upload to server:`
- `✅ [SCAN COMPLETE] Successfully uploaded:`
- `❌ [SCAN COMPLETE] Upload failed:`

### 3. Check Network Status
Ensure your device is connected to the same network as the Django server.

### 4. Verify Django Server Logs
Check your Django server console for incoming requests and any errors.

## What Should Happen Now:

1. **Scan Complete**: Shows "📱 [ScanName] saved locally" message
2. **If Online**: Attempts immediate upload to server
3. **Upload Success**: Shows "✅ [ScanName] uploaded to server successfully"  
4. **Upload Failure**: Shows "⚠️ [ScanName] failed to upload. Will retry when online."
5. **Scan List Updates**: Automatically refreshes to show new scan

## Common Issues:

### Auth Token Missing
- Check if Flutter app has logged in and stored auth token
- Check UserDefaults for token storage
- Add token to login flow if missing

### Network Issues  
- Check device and server are on same WiFi
- Try curl test from same network as device
- Check server IP address is correct

### Django Server Issues
- Check server is running and accessible
- Check CORS settings if making requests from browser
- Check authentication settings in Django settings.py

## Server Test Commands:

```bash
# Test server connectivity
curl -v http://192.168.1.5:9000/api/v1/scans/ --connect-timeout 5

# Test with auth token (replace YOUR_TOKEN)
curl -H "Authorization: Token YOUR_TOKEN" http://192.168.1.5:9000/api/v1/scans/

# Create test scan (replace YOUR_TOKEN)
curl -X POST -H "Authorization: Token YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title": "Test Scan", "description": "Test from curl", "duration": 60, "area_covered": 10.5, "height": 2.0, "data_size_mb": 1.2, "location": "Test Location"}' \
  http://192.168.1.5:9000/api/v1/scans/
```
