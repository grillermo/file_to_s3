# frozen_string_literal: true

ENV["AUTH_TOKEN"] = "test-token"

require "minitest/autorun"
require "fileutils"
require "rack"
require "rack/mock_request"
require "tmpdir"
require_relative "../app"

class AppTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("file-to-s3-test-")
    ENV["FILES_DIR"] = @dir
    @app = FileToS3App.new
  end

  def teardown
    ENV.delete("FILES_DIR")
    FileUtils.remove_entry(@dir)
  end

  # --- helpers ---------------------------------------------------------

  def write_temp(name, content)
    path = File.join(@dir, "..", "src-#{name}")
    File.write(path, content)
    path
  end

  def upload(path, filename, query: "")
    file = Rack::Multipart::UploadedFile.new(
      path, "application/octet-stream", true, filename: filename
    )
    env = Rack::MockRequest.env_for(
      "http://files.example/upload#{query}",
      method: "POST",
      params: { "file" => file },
      "HTTP_AUTHORIZATION" => "Bearer test-token"
    )
    @app.call(env)
  end

  def get(path)
    @app.call(Rack::MockRequest.env_for("http://files.example#{path}", method: "GET"))
  end

  def head(path)
    @app.call(Rack::MockRequest.env_for("http://files.example#{path}", method: "HEAD"))
  end

  def stored(name, content)
    File.write(File.join(@dir, name), content)
  end

  # --- files_dir override ----------------------------------------------

  def test_uploads_land_in_the_files_dir_override
    src = write_temp("a.txt", "hello")
    status, _, body = upload(src, "a.txt")

    assert_equal 200, status
    name = body.join.split("/files/").last
    assert_path_exists File.join(@dir, name)
  end

  # --- HEAD -------------------------------------------------------------

  def test_head_on_an_existing_file_matches_get
    stored("thing.plist", "<plist/>")

    get_status, get_headers, = get("/files/thing.plist")
    head_status, head_headers, head_body = head("/files/thing.plist")

    assert_equal 200, get_status
    assert_equal get_status, head_status
    assert_equal get_headers["content-type"], head_headers["content-type"]
    assert_equal "", head_body.to_a.join
  end

  def test_head_reports_the_length_without_a_body
    stored("thing.ipa", "0123456789")

    _, headers, body = head("/files/thing.ipa")

    assert_equal "10", headers["content-length"]
    assert_equal "", body.to_a.join
  end

  def test_head_on_a_missing_file_is_404
    status, = head("/files/nope.txt")

    assert_equal 404, status
  end
end
