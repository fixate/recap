# Inspired by [this blog post](https://github.com/blog/470-deployment-script-spring-cleaning), this
# recipe uses git's strengths to deploy applications faster and more simply than the standard
# capistrano deployment.  It deploys apps to a single directory. with no shared, current or releases
# folders and no symlinking.

require 'tomafro/deploy/capistrano_extensions'
require 'tomafro/deploy/bundler'
require 'tomafro/deploy/foreman'

Capistrano::Configuration.instance(:must_exist).load do
  # The [CapistranoExtensions](deploy/capistrano_extensions.html) module includes some useful shortcuts to make working with capistrano
  # easier.
  extend Tomafro::Deploy::CapistranoExtensions

  # To use this recipe, both the application's name and its git repository are required.
  set(:application) { abort "You must set the name of your application in your Capfile, e.g.: set :application, 'tomafro.net'" }
  set(:repository) { abort "You must set the git respository location in your Capfile, e.g.: set :respository, 'git@github.com/tomafro/tomafro.net'"}

  # The recipe assumes that the application code will be run as a dedicated user, with any user who
  # deploys the code added as a member of the application's group.  By default, both the user and
  # group are given the same name as the application.
  set(:application_user) { application }
  set(:application_group) { application_user }

  # Deployments can be made from any branch. `master` is used by default.
  set(:branch, 'master')

  # Unlike a standard capistrano deployment, all releases are stored directly in the `deploy_to`
  # directory.  The default is `/var/apps/#{application}`, but any location can be used.
  set(:deploy_to)   { "/var/apps/#{application}" }

  # Each release is marked by a unique tag, generated with the current timestamp.
  set(:release_tag) { "#{Time.now.utc.strftime("%Y%m%d%H%M%S")}"}

  # On tagging a release, a message is also recorded alongside the tag.  This message can contain
  # anything - its contents are ignored by the recipe.
  set(:release_message, "Deployed at #{Time.now}")

  # Some tasks need to know the `latest_tag`, which is the most recent successful deployment.  If no
  # deployments have been made, this will be `nil`.
  set(:latest_tag) { latest_tag_from_repository }

  # To authenticate with github or other git servers, it is easier (and cleaner) to forward the
  # deploying user's ssh key than fiddle with keys on a server.
  ssh_options[:forward_agent] = true

  # If key forwarding isn't possible, git may show a password prompt, which stalls capistrano unless
  # `:pty` is set to `true`.
  default_run_options[:pty] = true

  namespace :deploy do
    # The `deploy:setup` task prepares all the servers for the deployment.
    desc "Prepare servers for deployment"
    task :setup, :except => {:no_release => true} do
      transaction do
        clone_code
        change_ownership
      end
    end

    # The deployment directory is created and the repository is cloned into it.
    task :clone_code, :except => {:no_release => true} do
      on_rollback { run "rm -rf #{deploy_to}"}
      run "mkdir -p #{deploy_to}"
      git "clone #{repository} #{deploy_to}"
    end

    # All files are modified to be owned by the application group, and both readable and writable
    # by any member of that group (deploying users and the application itself).
    task :change_ownership, :except => {:no_release => true} do
      sudo "chown -R :#{application_group} #{deploy_to}"
      sudo "chmod -R g+srw #{deploy_to}"
    end

    # The main deployment task (called with `cap deploy`).
    desc "Deploy the latest application code"
    task :default do
      transaction do
        update_code
        change_ownership
        tag
      end
      restart
    end

    # Fetch the latest changes, then update `HEAD` to the deployment branch.
    task :update_code, :except => {:no_release => true} do
      on_rollback { git "reset --hard #{latest_tag}" if latest_tag }
      git "fetch"
      git "reset --hard origin/#{branch}"
    end

    # Tag `HEAD` with the release tag and message
    task :tag, :except => {:no_release => true} do
      on_rollback { git "tag -d #{current_tag}" }
      git "tag #{release_tag} -m '#{release_message}'"
    end

    # After a successful deployment, the app is restarted.  By default, this does nothing. It
    # should be overridden either in the main `Capfile` or in another recipe.
    desc "Restart the application following a deploy"
    task :restart do
    end

    # To rollback a release, the latest tag is deleted, and `HEAD` reset to the previous release
    # (if one exists).
    desc "Rollback to the previous release"
    namespace :rollback do
      task :default do
        if latest_tag
          git "tag -d #{latest_tag}"
          if previous_tag = latest_tag_from_repository
            git "reset --hard #{previous_tag}"
          end
        end
      end
    end
  end
end
