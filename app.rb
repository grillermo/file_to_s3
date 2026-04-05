require "dotenv/load"
require "aws-sdk-s3"
require "rack"
require "securerandom"

class FileToS3App
  MAX_FILE_SIZE = 25 * 1024 * 1024

  def call(env)
    req = Rack::Request.new(env)

    case [req.request_method, req.path_info]
    in ["GET", "/"]
      ok(render_form)
    in ["POST", "/upload"]
      handle_upload(req)
    else
      not_found
    end
  rescue StandardError => e
    error_page(e)
  end

  private

  def handle_upload(req)
    uploaded = req.params["file"]

    return unprocessable("Choose a file before submitting.") unless uploaded.is_a?(Hash)

    tempfile = uploaded[:tempfile]
    filename = sanitize_filename(uploaded[:filename])

    return unprocessable("The uploaded file payload was invalid.") unless tempfile && filename

    size = tempfile.size
    return unprocessable("The file is empty.") if size.zero?
    return unprocessable("Files larger than #{MAX_FILE_SIZE / (1024 * 1024)} MB are not allowed.") if size > MAX_FILE_SIZE

    key = build_object_key(filename)
    content_type = uploaded[:type].to_s
    bucket = ENV.fetch("AWS_S3_BUCKET")

    s3_client.put_object(
      bucket: bucket,
      key: key,
      body: tempfile,
      content_type: content_type.empty? ? "application/octet-stream" : content_type
    )

    ok(render_success(bucket:, key:, filename:))
  end

  def s3_client
    @s3_client ||= Aws::S3::Client.new(
      region: ENV.fetch("AWS_REGION"),
      credentials: Aws::Credentials.new(
        ENV.fetch("AWS_CLIENT_ID"),
        ENV.fetch("AWS_SECRET")
      )
    )
  end

  def build_object_key(filename)
    prefix = ENV.fetch("AWS_S3_PREFIX", "uploads").sub(%r{/\z}, "")
    [prefix, "#{SecureRandom.uuid}-#{filename}"].reject(&:empty?).join("/")
  end

  def sanitize_filename(filename)
    return nil if filename.to_s.strip.empty?

    File.basename(filename).gsub(/[^\w.\-]/, "_")
  end

  def ok(body)
    html_response(200, body)
  end

  def unprocessable(message)
    html_response(422, render_form(error_message: message))
  end

  def not_found
    html_response(404, page_template("Not found", "<p>The page you requested does not exist.</p>"))
  end

  def error_page(error)
    warn "[file-to-s3] #{error.class}: #{error.message}"
    html_response(500, page_template("Upload failed", "<p>#{h(error.message)}</p>"))
  end

  def html_response(status, body)
    [status, { "content-type" => "text/html; charset=utf-8" }, [body]]
  end

  def render_form(error_message: nil)
    error_block = error_message ? %(<p class="error">#{h(error_message)}</p>) : ""

    page_template("Upload a file to S3", <<~HTML)
      #{error_block}
      <form action="/upload" method="post" enctype="multipart/form-data">
        <label for="file">Choose a file</label>
        <input id="file" name="file" type="file" required>
        <button type="submit">Upload</button>
      </form>
    HTML
  end

  def render_success(bucket:, key:, filename:)
    page_template("Upload complete", <<~HTML)
      <p><strong>#{h(filename)}</strong> was uploaded successfully.</p>
      <dl>
        <dt>Bucket</dt>
        <dd>#{h(bucket)}</dd>
        <dt>Object key</dt>
        <dd><code>#{h(key)}</code></dd>
      </dl>
      <p><a href="/">Upload another file</a></p>
    HTML
  end

  def page_template(title, body)
    <<~HTML
      <!doctype html>
      <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>#{h(title)}</title>
          <style>
            :root {
              color-scheme: light;
              font-family: "Iowan Old Style", "Palatino Linotype", serif;
              background: linear-gradient(135deg, #f2efe8, #dfe9f3);
              color: #1d2433;
            }

            body {
              margin: 0;
              min-height: 100vh;
              display: grid;
              place-items: center;
              padding: 2rem;
            }

            main {
              width: min(100%, 34rem);
              background: rgba(255, 255, 255, 0.88);
              border: 1px solid rgba(29, 36, 51, 0.14);
              border-radius: 1rem;
              box-shadow: 0 24px 60px rgba(29, 36, 51, 0.14);
              padding: 2rem;
              backdrop-filter: blur(12px);
            }

            h1 {
              margin-top: 0;
            }

            form, dl {
              display: grid;
              gap: 1rem;
            }

            input, button {
              font: inherit;
            }

            button {
              justify-self: start;
              border: 0;
              border-radius: 999px;
              background: #1d5b79;
              color: white;
              padding: 0.75rem 1.2rem;
              cursor: pointer;
            }

            .error {
              color: #9f1d35;
              font-weight: 700;
            }

            code {
              word-break: break-all;
            }

            dt {
              font-weight: 700;
            }

            dd {
              margin: 0;
            }
          </style>
        </head>
        <body>
          <main>
            <h1>#{h(title)}</h1>
            #{body}
          </main>
        </body>
      </html>
    HTML
  end

  def h(value)
    Rack::Utils.escape_html(value.to_s)
  end
end
