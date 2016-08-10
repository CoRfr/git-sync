#!/usr/bin/env ruby

$LOAD_PATH << File.dirname(__FILE__)
require 'common'

require 'minitest/autorun'
require 'rack/test'
require 'base64'

class TestGerrit < Minitest::Test

  def setup()
  end

  def teardown()
  end

  def test_event()
    src = GitSync::Source::Gerrit.new("gerrit", 29418, nil, "from", "to")

    line = '{"author":{"name":"Jenkins","email":"jenkins@sierrawireless.com","username":"jenkins"},"comment":"Patch Set 3:\n\nBuild Successful \n\nhttp://jenkins/job/Legato-Merged/104/ : SUCCESS","patchSet":{"number":"3","revision":"8ddc03b9be017ed3ab17f56bfea6272cc92dc4c2","parents":["16211caa7b58b0365dd28e7d9353d54c64751e13"],"ref":"refs/changes/55/7755/3","uploader":{"name":"Gildas Seimbille","email":"gseimbille@sierrawireless.com","username":"gseimbille"},"createdOn":1467037232,"author":{"name":"Gildas Seimbille","email":"gseimbille@sierrawireless.com","username":"gseimbille"},"isDraft":false,"kind":"REWORK","sizeInsertions":32,"sizeDeletions":-23},"change":{"project":"Legato/platformAdaptor/at","branch":"master","id":"I2e5354f13d1ad71102d5b34b2d8e43b69c56d501","number":"7755","subject":"[RasPi] Fix PA AT initialization","owner":{"name":"Gildas Seimbille","email":"gseimbille@sierrawireless.com","username":"gseimbille"},"url":"https://gerrit/7755","commitMessage":"[RasPi] Fix PA AT initialization\n\nFix a little problem in the AT platform adaptor initialization.\n(functions were not in the right order)\n\nResolves: LE-5294\nChange-Id: I2e5354f13d1ad71102d5b34b2d8e43b69c56d501\n","status":"MERGED"},"type":"comment-added","eventCreatedOn":1467039668}
'
    got_line = false
    src.process_event(line) do |event|
      got_line = true
    end

    assert got_line
  end
end
