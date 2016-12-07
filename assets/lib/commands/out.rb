#!/usr/bin/env ruby

require 'json'
require 'octokit'
require_relative 'base'
require_relative '../repository'
require_relative '../status'

module Commands
  class Out < Commands::Base
    attr_reader :destination

    def initialize(destination:, input: Input.instance)
      @destination = destination

      super(input: input)
    end

    def output
      check_defaults!
      path = File.join(destination, params['path'])
      raise %(`path` "#{params['path']}" does not exist) unless File.exist?(path)

      if params.comment
        comment_path = File.join(destination, params.comment)
        raise %(`comment` "#{params.comment}" does not exist) unless File.exist?(comment_path)
      end

      if params.merge_commit_msg
        commit_path = File.join(destination, params.merge_commit_msg)
        raise %(`merge_commit_msg` "#{params.merge_commit_msg}" does not exist) unless File.exist?(commit_path)
      end

      id  = Dir.chdir(path) { `git config --get pullrequest.id`.chomp }
      sha = Dir.chdir(path) { `git rev-parse HEAD`.chomp }

      repo = Repository.new(name: input.source.repo)

      metadata = [{ 'name' => 'status', 'value' => params['status'] }]
      if id.empty?
        version = { 'ref' => sha }
      else
        pr = PullRequest.from_github(repo: repo, id: id)
        metadata << { 'name' => 'url', 'value' => pr.url }
        version = { 'pr' => id, 'ref' => sha }
      end

      atc_url = input.source.base_url || ENV['ATC_EXTERNAL_URL']
      context = params.context || 'status'

      Status.new(
        state: params.status,
        atc_url: atc_url,
        sha: sha,
        repo: repo,
        context: context
      ).create!

      if params.comment
        comment_path = File.join(destination, params.comment)
        comment = File.read(comment_path, encoding: Encoding::UTF_8)
        Octokit.add_comment(input.source.repo, id, comment)
        metadata << { 'name' => 'comment', 'value' => comment }
      end

      if params.merge
        commit_msg = if params.merge_commit_msg
          commit_path = File.join(destination, params.merge_commit_msg)
          File.read(commit_path, encoding: Encoding::UTF_8)
        else
          ""
        end
        Octokit.merge_pull_request(input.source.repo, id, commit_msg, merge_method: params.merge, accept: 'application/vnd.github.polaris-preview')
        metadata << { 'name' => 'merge', 'value' => params.merge }
        metadata << { 'name' => 'merge_commit_msg', 'value' => commit_msg }
      end


      {
        'version' => version,
        'metadata' => metadata
      }
    end

    private

    def params
      input.params
    end

    def check_defaults!
      raise %(`status` "#{params.status}" is not supported -- only success, failure, error, or pending) unless %w(success failure error pending).include?(params.status)
      raise %(`merge` "#{params.merge}" is not supported -- only merge, squash, or rebase) if params.merge && !%w(merge squash rebase).include?(params.merge)
      raise '`path` required in `params`' unless params.path
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  destination = ARGV.shift
  command = Commands::Out.new(destination: destination)
  puts JSON.generate(command.output)
end