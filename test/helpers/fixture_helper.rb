# test/helpers/fixture_helper.rb
module FixtureHelper
  FIXTURE_PATH = File.join(__dir__, '..', 'fixtures')
  
  def self.load_json(path)
    file_path = File.join(FIXTURE_PATH, "#{path}.json")
    JSON.parse(File.read(file_path))
  end
  
  def self.load_text(path)
    File.read(File.join(FIXTURE_PATH, path))
  end
  
  def self.drive_response(name)
    load_json("drive_responses/#{name}")
  end
  
  def self.document_sample(name)
    load_text("documents/#{name}")
  end
  
  def self.mock_drive_file(id: 'test_file_id', name: 'test.txt', content: 'Test content')
    {
      'id' => id,
      'name' => name,
      'mimeType' => 'text/plain',
      'content' => content,
      'modifiedTime' => Time.now.iso8601
    }
  end
end
