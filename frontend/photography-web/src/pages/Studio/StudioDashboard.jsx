import { useCallback, useEffect, useState } from "react";
import StudioProfile from "./StudioProfile";
import StudioPortfolio from "./StudioPortfolio";
import StudioServices from "./StudioServices";
import StudioAvailability from "./StudioAvailability";
import StudioPackages from "./StudioPackages";
import StudioDashboardOverview from "./StudioDashboardOverview";
import StudioLayout from "./StudioLayout";
import { useAuth } from "../../context/useAuth";
import { deleteStudioProfile, getStudioProfile, saveStudioProfile } from "../../services/studioProfileService";
import { createPortfolioItem, deletePortfolioItem, getStudioPortfolio, updatePortfolioItem } from "../../services/studioPortfolioService";
import { createStudioService, deleteStudioService, getStudioServices, updateStudioService } from "../../services/studioServicesService";
import { createStudioAvailability, deleteStudioAvailability, getStudioAvailability, updateStudioAvailability } from "../../services/studioAvailabilityService";
import { createPhotographyPackage, deletePhotographyPackage, getPhotographyPackages, updatePhotographyPackage } from "../../services/photographyPackagesService";
import { createPackageAddon, deletePackageAddon, getPackageAddons, updatePackageAddon } from "../../services/packageAddonsService";
import "./StudioDashboard.css";

const profileCompletionFields = ["studioName", "description", "location", "address", "contactNumber", "email", "experienceYears", "photographyTypes", "startingPrice", "logoUrl", "coverPhotoUrl"];
const pageDetails = {
  profile: ["PROFILE", "Profile", "Manage your studio identity, contact details, profile picture, and cover photo."],
  availability: ["AVAILABILITY", "Availability", "Manage the dates and times when clients can book your studio."],
  portfolio: ["PORTFOLIO", "Portfolio", "Showcase your best photography work."],
  services: ["SERVICES", "Services", "Manage the photography services and packages you offer."],
  packages: ["PACKAGES", "Packages", "Create and manage photography packages for your customers."],
};

function hasProfileValue(profile, field) {
  const value = profile?.[field];
  if (field === "experienceYears" || field === "startingPrice") return Number.isFinite(Number(value)) && Number(value) > 0;
  return typeof value === "string" && value.trim().length > 0;
}

function StudioDashboard({ page = "dashboard" }) {
  const { token } = useAuth();
  const [profile, setProfile] = useState(null);
  const [failedHeroLogoUrl, setFailedHeroLogoUrl] = useState("");
  const [isProfileLoading, setIsProfileLoading] = useState(true);
  const [profileError, setProfileError] = useState("");
  const [portfolioItems, setPortfolioItems] = useState([]);
  const [isPortfolioLoading, setIsPortfolioLoading] = useState(true);
  const [portfolioError, setPortfolioError] = useState("");
  const [services, setServices] = useState([]);
  const [areServicesLoading, setAreServicesLoading] = useState(true);
  const [servicesError, setServicesError] = useState("");
  const [availability, setAvailability] = useState([]);
  const [isAvailabilityLoading, setIsAvailabilityLoading] = useState(true);
  const [availabilityError, setAvailabilityError] = useState("");
  const [packages, setPackages] = useState([]);
  const [packagesLoading, setPackagesLoading] = useState(true);
  const [packagesError, setPackagesError] = useState("");

  const loadProfile = useCallback(async () => {
    setIsProfileLoading(true); setProfileError("");
    try { setProfile(await getStudioProfile(token)); }
    catch (error) { setProfileError(error.message || "Unable to load the studio profile."); }
    finally { setIsProfileLoading(false); }
  }, [token]);
  const loadPortfolio = useCallback(async () => {
    setIsPortfolioLoading(true); setPortfolioError("");
    try { const items = await getStudioPortfolio(token); setPortfolioItems(Array.isArray(items) ? items : []); if (!Array.isArray(items)) setPortfolioError("The server returned an invalid portfolio response."); }
    catch (error) { setPortfolioError(error.message || "Unable to load the studio portfolio."); }
    finally { setIsPortfolioLoading(false); }
  }, [token]);
  const loadServices = useCallback(async () => {
    setAreServicesLoading(true); setServicesError("");
    try { const items = await getStudioServices(token); setServices(Array.isArray(items) ? items : []); if (!Array.isArray(items)) setServicesError("The server returned an invalid services response."); }
    catch (error) { setServicesError(error.message || "Unable to load studio services."); }
    finally { setAreServicesLoading(false); }
  }, [token]);
  const loadAvailability = useCallback(async () => {
    setIsAvailabilityLoading(true); setAvailabilityError("");
    try { const items = await getStudioAvailability(token); setAvailability(Array.isArray(items) ? items : []); if (!Array.isArray(items)) setAvailabilityError("The server returned an invalid availability response."); }
    catch (error) { setAvailabilityError(error.message || "Unable to load studio availability."); }
    finally { setIsAvailabilityLoading(false); }
  }, [token]);
  const loadPackages = useCallback(async () => { setPackagesLoading(true); setPackagesError(""); try { const items = await getPhotographyPackages(token); setPackages(Array.isArray(items) ? items : []); } catch (error) { setPackagesError(error.message || "Unable to load packages."); } finally { setPackagesLoading(false); } }, [token]);

  useEffect(() => {
    const loadTimer = window.setTimeout(() => {
      loadProfile();
      if (page === "dashboard" || page === "portfolio") loadPortfolio();
      if (page === "dashboard" || page === "services" || page === "packages") loadServices();
      if (page === "dashboard" || page === "availability") loadAvailability();
      if (page === "packages") loadPackages();
    }, 0);
    return () => window.clearTimeout(loadTimer);
  }, [page, loadProfile, loadPortfolio, loadServices, loadAvailability, loadPackages]);

  const saveProfile = async (values) => { await saveStudioProfile(token, values); await loadProfile(); };
  const deleteProfile = async () => { await deleteStudioProfile(token); setProfile(null); };
  const addPortfolioItem = async (values) => { const created = await createPortfolioItem(token, values); setPortfolioItems((current) => [created, ...current]); };
  const editPortfolioItem = async (id, values) => { const updated = await updatePortfolioItem(token, id, values); setPortfolioItems((current) => current.map((item) => item.id === id ? updated : item)); };
  const removePortfolioItem = async (id) => { await deletePortfolioItem(token, id); setPortfolioItems((current) => current.filter((item) => item.id !== id)); };
  const addService = async (values) => { const created = await createStudioService(token, values); setServices((current) => [...current, created].sort((a, b) => a.serviceName.localeCompare(b.serviceName))); };
  const editService = async (id, values) => { const updated = await updateStudioService(token, id, values); setServices((current) => current.map((service) => service.id === id ? updated : service).sort((a, b) => a.serviceName.localeCompare(b.serviceName))); };
  const removeService = async (id) => { await deleteStudioService(token, id); setServices((current) => current.filter((service) => service.id !== id)); };
  const addAvailability = async (values) => { const created = await createStudioAvailability(token, values); setAvailability((current) => [...current, created].sort((a, b) => a.date.localeCompare(b.date))); };
  const editAvailability = async (id, values) => { const updated = await updateStudioAvailability(token, id, values); setAvailability((current) => current.map((item) => item.id === id ? updated : item).sort((a, b) => a.date.localeCompare(b.date))); };
  const removeAvailability = async (id) => { await deleteStudioAvailability(token, id); setAvailability((current) => current.filter((item) => item.id !== id)); };
  const addPackage = async (values) => { const created = await createPhotographyPackage(token, values); setPackages((current) => [created, ...current]); };
  const editPackage = async (id, values) => { const updated = await updatePhotographyPackage(token, id, values); setPackages((current) => current.map((item) => item.id === id ? updated : item)); };
  const removePackage = async (id) => { await deletePhotographyPackage(token, id); setPackages((current) => current.filter((item) => item.id !== id)); };
  const loadPackageAddons = async (packageId) => getPackageAddons(token, packageId);
  const addPackageAddon = async (packageId, values) => createPackageAddon(token, packageId, values);
  const editPackageAddon = async (packageId, addonId, values) => updatePackageAddon(token, packageId, addonId, values);
  const removePackageAddon = async (packageId, addonId) => deletePackageAddon(token, packageId, addonId);

  const completedProfileFields = profileCompletionFields.filter((field) => hasProfileValue(profile, field)).length;
  const profileCompletion = Math.round((completedProfileFields / profileCompletionFields.length) * 100);
  const heading = pageDetails[page];

  return <StudioLayout page={page} profile={profile}>
      {heading && <section className="studio-route-heading"><p className="studio-kicker">{heading[0]}</p><h1>{heading[1]}</h1><p>{heading[2]}</p></section>}
      {page === "dashboard" && <StudioDashboardOverview profile={profile} profileLoading={isProfileLoading} profileError={profileError} profileCompletion={profileCompletion} portfolio={portfolioItems} portfolioLoading={isPortfolioLoading} portfolioError={portfolioError} services={services} servicesLoading={areServicesLoading} servicesError={servicesError} availability={availability} availabilityLoading={isAvailabilityLoading} availabilityError={availabilityError} failedLogoUrl={failedHeroLogoUrl} onLogoError={setFailedHeroLogoUrl} />}
      {page === "profile" && <section className="studio-layout studio-route-content"><StudioProfile profile={profile} isLoading={isProfileLoading} error={profileError} onSave={saveProfile} onDelete={deleteProfile} onRetry={loadProfile} /></section>}
      {page === "availability" && <section className="studio-route-content"><StudioAvailability items={availability} isLoading={isAvailabilityLoading} error={availabilityError} onRetry={loadAvailability} onCreate={addAvailability} onUpdate={editAvailability} onDelete={removeAvailability} /></section>}
      {page === "portfolio" && <div className="studio-route-content"><StudioPortfolio items={portfolioItems} isLoading={isPortfolioLoading} error={portfolioError} onRetry={loadPortfolio} onCreate={addPortfolioItem} onUpdate={editPortfolioItem} onDelete={removePortfolioItem} /></div>}
      {page === "services" && <div className="studio-route-content"><StudioServices services={services} isLoading={areServicesLoading} error={servicesError} onRetry={loadServices} onCreate={addService} onUpdate={editService} onDelete={removeService} /></div>}
      {page === "packages" && <div className="studio-route-content"><StudioPackages packages={packages} services={services} servicesLoading={areServicesLoading} servicesError={servicesError} packagesLoading={packagesLoading} error={packagesError} onRetry={loadPackages} onCreate={addPackage} onUpdate={editPackage} onDelete={removePackage} onLoadAddons={loadPackageAddons} onCreateAddon={addPackageAddon} onUpdateAddon={editPackageAddon} onDeleteAddon={removePackageAddon} /></div>}
  </StudioLayout>;
}

export default StudioDashboard;
