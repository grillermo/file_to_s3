# file-to-s3

Minimal Rack app that accepts a file upload and stores it in AWS S3.

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
bundle exec rackup
```

Then open http://localhost:9292

## Notes

- Uploads larger than 25 MB are rejected by the app.
- Object keys use a UUID prefix to avoid collisions.
- The app builds `Aws::Credentials` directly from `AWS_CLIENT_ID` and `AWS_SECRET`.
