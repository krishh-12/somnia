.PHONY: serve test ios

serve:
	uv run --project services/api uvicorn somnia.main:create_app --factory --host 127.0.0.1 --port 8090

test:
	uv run --project services/api pytest

ios:
	xcodegen generate --spec project.yml
	xcodebuild -project Somnia.xcodeproj -scheme Somnia -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.2' build CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO ONLY_ACTIVE_ARCH=YES
