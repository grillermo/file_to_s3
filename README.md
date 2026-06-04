# file-to-s3

Minimal headless Rack app that accepts a file upload and stores it in AWS S3.

## Requirements

- Ruby 3.2.4
- Bundler
- AWS S3 bucket
- AWS credentials exposed explicitly as `AWS_CLIENT_ID` and `AWS_SECRET`

## Setup

```sh
bundle install
cp .env.example .env
```

The app loads `.env` automatically on boot. Set these variables in `.env` or export them in your shell:

- `AWS_REGION`
- `AWS_S3_BUCKET`
- `AWS_CLIENT_ID` for the AWS access key ID used by the app
- `AWS_SECRET` for the AWS secret access key used by the app
- `AWS_S3_PREFIX` optional, defaults to `uploads`

Example:

```sh
AWS_REGION=us-east-1
AWS_S3_BUCKET=my-upload-bucket
AWS_CLIENT_ID=AKIA...
AWS_SECRET=super-secret-value
AWS_S3_PREFIX=uploads
```

## Run

```sh
bin/rackup -s webrick
```

The service listens on http://localhost:33333

The local `bin/rackup` wrapper defaults to port `33333`. You can still override it with `PORT=4567 bin/rackup -s webrick` or `bin/rackup -p 4567 -s webrick`.

If `bin/rackup` is missing, regenerate the local Bundler binstub once:

```sh
bundle binstub rackup --force
bin/rackup -s webrick
```

## Notes

- The app exposes `POST /upload` and `POST /receive`.
- Uploads larger than 25 MB are rejected by the app.
- Object keys use a UUID prefix to avoid collisions.
- The app builds `Aws::Credentials` directly from `AWS_CLIENT_ID` and `AWS_SECRET`.

## API

Send a `multipart/form-data` request with a `file` field:

```sh
curl -X POST http://localhost:33333/upload \
  -F "file=@/path/to/file.txt"
```

On success, the response is `200 text/plain` with the uploaded object's S3 URL in the response body.

To store the file locally under `files/` without uploading it to S3:

```sh
curl -X POST http://localhost:33333/receive \
  -F "file=@/path/to/file.txt"
```

On success, the response is `200 text/plain` after the local file has been written.
