module Match
  class Runner
    attr_accessor :changes_to_commit

    def run(params)
      FastlaneCore::PrintTable.print_values(config: params,
                                         hide_keys: [:workspace],
                                             title: "Summary for match #{Match::VERSION}")

      params[:workspace] = GitHelper.clone(params[:git_url])

      cert_path = certificate(params: params)
      uuid = profile(params: params, 
                     certificate_id: File.basename(cert_path).gsub(".cer", ""))
      

      if self.changes_to_commit
        message = GitHelper.generate_commit_message(params)
        GitHelper.commit_changes(params[:workspace], message, params[:git_url])
      else
        GitHelper.clear_changes
      end

      TablePrinter.print_summary(params, uuid)

      UI.success "All required keys, certificates and provisioning profiles are installed 🙌".green
    end

    def certificate(params: nil)
      cert_type = :distribution
      cert_type = :development if params[:type] == "development"

      certs = Dir[File.join(params[:workspace], "certs", cert_type.to_s, "*.cer")]
      keys = Dir[File.join(params[:workspace], "certs", cert_type.to_s, "*.p12")]

      if certs.count == 0 or keys.count == 0
        UI.important "Couldn't find a valid code signing identity in the git repo for #{cert_type}... creating one for you now"
        UI.crash!("No code signing identity found and can not create a new one because you enabled `readonly`") if params[:readonly]
        cert_path = Generator.generate_certificate(params, cert_type)
        self.changes_to_commit = true
      else
        cert_path = certs.last
        UI.message "Installing certificate..."

        if FastlaneCore::CertChecker.installed?(cert_path)
          UI.verbose "Certificate '#{File.basename(cert_path)}' is already installed on this machine"
        else
          Utils.import(cert_path, params[:keychain_name])
        end

        # Import the private key
        # there seems to be no good way to check if it's already installed - so just install it
        Utils.import(keys.last, params[:keychain_name])
      end

      return cert_path
    end

    def profile(params: nil, certificate_id: nil)
      prov_type = params[:type].to_sym

      profile_name = [prov_type.to_s, params[:app_identifier]].join("_").gsub("*", '\*') # this is important, as it shouldn't be a wildcard
      profiles = Dir[File.join(params[:workspace], "profiles", prov_type.to_s, "#{profile_name}.mobileprovision")]

      # Install the provisioning profiles
      profile = profiles.last
      if profile.nil? or params[:force]
        UI.crash!("No matching provisioning profiles found and can not create a new one because you enabled `readonly`") if params[:readonly]
        profile = Generator.generate_provisioning_profile(params: params, 
                                                       prov_type: prov_type, 
                                                  certificate_id: certificate_id)
        self.changes_to_commit = true
      end

      FastlaneCore::ProvisioningProfile.install(profile)

      parsed = FastlaneCore::ProvisioningProfile.parse(profile)
      uuid = parsed["UUID"]
      Utils.fill_environment(params, uuid)

      return uuid
    end
  end
end
