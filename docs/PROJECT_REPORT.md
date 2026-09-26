# SnapSync AI
## Intelligent Photography Booking & Management Platform

## 1. Introduction

SnapSync AI is an intelligent photography booking and management platform developed to simplify the process of finding photography studios, selecting suitable services, managing bookings, and coordinating photography-related activities.

The system provides both web and mobile applications that operate through a common ASP.NET Core backend and PostgreSQL database. The web application mainly supports studio owners and administrators, while the mobile application provides customer-oriented features such as studio discovery, package selection, booking management, and AI-assisted recommendations.

A key feature of SnapSync AI is its Agentic AI workflow. Instead of using AI only as a chatbot, the system uses multiple specialized agents to assist with studio matching, package recommendation, scheduling, and validation. Human approval and deterministic backend validation are included to ensure that AI-generated recommendations do not directly perform unsafe or unauthorized business operations.


## 2. Problem Statement

Customers who require photography services often need to search through different studios, compare services and packages, check availability, communicate their requirements, and manually coordinate suitable dates and times. This process can be time-consuming and may make it difficult for customers to identify an option that matches their location, budget, photography type, and required services.

Photography studios also need to manage portfolios, services, availability, bookings, and customer requests using consistent information. When these activities are handled separately or manually, maintaining accurate availability and coordinating bookings becomes more difficult.

SnapSync AI addresses these problems by providing a centralized platform where customers, studio owners, and administrators can manage the photography booking process through a shared system.


## 3. Proposed Solution

The proposed solution is a full-stack photography booking and management platform consisting of a React web application, Flutter mobile application, ASP.NET Core Web API, PostgreSQL database, and a Python-based Agentic AI service.

Customers can browse studios, view portfolios and services, check available information, select photography packages, create bookings, track booking progress, and provide reviews through the mobile application.

Studio owners can manage their studio profile, portfolio, services, availability, bookings, and AI-generated recommendation requests through the web application. Administrators can monitor and manage important system information through the administration interface.

The Agentic AI workflow assists customers through four specialized agents: Studio Matching, Package Recommendation, Scheduling, and Validation & Safety. AI-generated recommendations are passed through backend validation and human review instead of automatically creating bookings.

The system also integrates location-based functionality to support studio discovery and distance-related operations.


## 4. Project Scope

The scope of SnapSync AI covers the main activities required to connect customers with photography studios and manage the booking lifecycle.

The system includes four major functional components:

1. **Studio & Portfolio Management** – manages studio profiles, portfolio content, studio services, availability, and location information.

2. **Package & Service Management** – manages photography packages, included services, pricing information, customization options, and package-related customer selections.

3. **Booking & Scheduling Management** – manages booking creation, scheduling, booking status, booking history, pricing validation, availability checks, and booking conflicts.

4. **Customer & Review Management** – manages customer-related information, reviews, feedback, and interactions associated with completed photography services.

The project also includes an Agentic AI workflow containing four specialized agents for studio matching, package recommendation, scheduling, and validation. The AI workflow supports the booking decision process but does not independently create authoritative bookings.

The platform uses a common ASP.NET Core API and PostgreSQL database for both React and Flutter applications. Authentication, authorization, validation, and important business rules are handled by the backend to maintain consistency between platforms.

## 5. System Users and Roles

SnapSync AI supports three main user roles: Customer, Studio Owner, and Administrator. Each role has different responsibilities and permissions within the system.

### 5.1 Customer

Customers mainly interact with the system through the Flutter mobile application.

A customer can:

- Register and log in to the system.
- Browse available photography studios.
- View studio profiles and portfolios.
- View photography services and packages.
- Search for suitable studios.
- View studio availability.
- Select and customize photography packages.
- Select booking dates and times.
- Create and manage photography bookings.
- View booking details and booking status.
- Track the progress of a booking.
- Submit reviews and feedback.
- Request AI-assisted photography recommendations.
- View the status and result of AI recommendation workflows.

### 5.2 Studio Owner

Studio owners mainly use the React web application to manage their photography business information and customer requests.

A studio owner can:

- Log in securely to the system.
- Create and update the studio profile.
- Manage studio information and location.
- Upload and manage portfolio content.
- Manage photography services and packages.
- Manage pricing and package-related information.
- Manage studio availability.
- View and manage customer bookings.
- Update booking-related information where authorized.
- View AI-generated proposals associated with the studio.
- Approve or reject AI-generated recommendations after review.

### 5.3 Administrator

Administrators use the web application to monitor and manage the overall platform.

An administrator can:

- Access the administrative dashboard.
- Manage registered studios.
- Manage customer information.
- Monitor bookings.
- Monitor customer reviews.
- Access administrative reports.
- Review relevant AI workflow information.
- Perform authorized administrative operations.

Role-based authorization is enforced by the ASP.NET Core backend so that users can access only the operations permitted for their role.


## 6. Functional Requirements

Functional requirements describe the main operations that the SnapSync AI platform must provide.

### 6.1 Authentication and Authorization

The system shall:

- Allow users to register and log in.
- Authenticate users before providing access to protected functions.
- Use role-based authorization for Customer, Studio Owner, and Administrator operations.
- Protect backend endpoints from unauthorized access.
- Obtain authenticated user identity from the backend authentication context rather than trusting client-supplied identity information.

### 6.2 Studio and Portfolio Management

The system shall:

- Allow a studio owner to create and update studio information.
- Allow a studio owner to manage studio location information.
- Allow portfolio images and albums to be managed.
- Allow customers to view public studio profiles.
- Allow customers to view studio portfolios.
- Allow studio services to be created, updated, viewed, and managed.
- Allow studio availability information to be maintained.
- Support location-based studio discovery.

### 6.3 Package and Service Management

The system shall:

- Allow photography packages and services to be maintained.
- Store package pricing and duration information.
- Support package customization where applicable.
- Support additional service selections.
- Support extra coverage hours where applicable.
- Support additional photographer-related pricing where applicable.
- Calculate final pricing using authoritative backend information.
- Prevent the client application from being treated as the authoritative source for booking prices.

### 6.4 Booking and Scheduling Management

The system shall:

- Allow authenticated customers to create photography bookings.
- Associate a booking with the authenticated customer.
- Validate the selected studio, package, and services.
- Validate studio availability before accepting relevant booking operations.
- Detect conflicting bookings.
- Calculate booking prices on the server.
- Maintain booking status information.
- Maintain booking status history.
- Allow customers to view their bookings.
- Allow authorized studio owners to manage relevant bookings.
- Prevent unauthorized users from modifying bookings belonging to other users or studios.

### 6.5 Customer and Review Management

The system shall:

- Maintain customer-related information.
- Allow customers to access their relevant booking information.
- Allow eligible customers to submit reviews.
- Store ratings and feedback.
- Allow relevant reviews to be displayed and managed.
- Allow administrators to monitor review information.

### 6.6 Agentic AI Workflow

The system shall provide four distinct AI agents:

1. Studio Matching Agent
2. Package Recommendation Agent
3. Scheduling Agent
4. Validation and Safety Agent

The Agentic AI workflow shall:

- Accept customer photography requirements through the application.
- Match customer requirements with suitable studio information.
- Recommend an appropriate photography package.
- Suggest suitable scheduling information.
- Validate the generated recommendation before human review.
- Produce structured workflow results.
- Persist workflow state through the ASP.NET Core backend.
- Maintain an auditable workflow event history.
- Fail safely when an AI recommendation cannot be completed.

The AI service shall not directly create bookings or modify authoritative application data.

### 6.7 Human Approval

The system shall:

- Present generated AI proposals for authorized human review.
- Allow an authorized studio owner or administrator to approve an AI proposal.
- Allow an authorized studio owner or administrator to reject an AI proposal.
- Maintain proposal versions.
- Perform fresh deterministic validation before approval.
- Detect stale or invalid recommendations.
- Move invalid recommendations to an appropriate revalidation state.
- Record approval and rejection information for auditing.

Approval of an AI recommendation shall not bypass the normal booking validation process.

### 6.8 Search, Filtering and Reporting

Where applicable, the system shall support:

- Searching records.
- Filtering records.
- Sorting records.
- Pagination for collections of records.
- Administrative reporting.
- Status-based filtering and management.

These capabilities improve usability when the number of studios, customers, bookings, reviews, and AI workflows increases.


## 7. Non-Functional Requirements

Non-functional requirements describe the expected quality, security, reliability, and maintainability characteristics of SnapSync AI.

### 7.1 Security

The system should:

- Protect private API endpoints using authentication and authorization.
- Apply role-based access control.
- Keep database credentials outside source-controlled configuration.
- Keep JWT signing keys secure.
- Keep the Gemini API key on the server side.
- Keep internal AI workflow tokens inaccessible to client applications.
- Validate important data on the backend.
- Prevent clients from directly accessing the database.
- Prevent React and Flutter applications from directly accessing Gemini or the internal Python AI service.

### 7.2 Reliability

The system should:

- Prevent AI failures from creating incomplete bookings.
- Maintain durable AI workflow states.
- Maintain booking and AI workflow histories where required.
- Handle external AI service failures safely.
- Revalidate important business information before AI proposal approval.
- Detect booking conflicts before accepting relevant booking operations.

### 7.3 Performance

The system should:

- Respond to normal API requests within an acceptable time under expected project usage.
- Perform database queries efficiently.
- Avoid unnecessary network requests.
- Use pagination for potentially large data collections.
- Keep long-running AI operations separated from normal client-side business logic.

Performance testing should be carried out to evaluate important API operations under expected workloads.

### 7.4 Usability

The system should:

- Provide clear navigation in both web and mobile applications.
- Display understandable validation and error messages.
- Provide loading and processing feedback for operations that may take time.
- Provide clear booking status information.
- Provide clear AI workflow status information.
- Maintain consistent interaction patterns across related screens.

### 7.5 Maintainability

The system should:

- Separate frontend, backend, mobile, database, and AI responsibilities.
- Organize functionality into understandable modules and services.
- Maintain reusable components where appropriate.
- Keep business rules primarily within the authoritative backend.
- Maintain architecture decision records for important technical decisions.
- Use version control to track project changes.

### 7.6 Scalability

The architecture should allow major components such as the React application, ASP.NET Core API, PostgreSQL database, and Python AI service to be deployed and managed independently when required.

### 7.7 Compatibility

The system should:

- Support the React web application through modern web browsers.
- Support the Flutter application on its intended mobile platform.
- Provide REST API communication using standard HTTP and JSON.
- Maintain consistent backend business rules for both web and mobile clients.

### 7.8 Auditability

Important AI operations should be traceable.

The system should maintain:

- AI workflow state.
- Workflow events.
- Proposal versions.
- Human approval or rejection information.
- Relevant booking status history.

This information supports debugging, demonstration, and investigation of important system actions.

### 7.9 Testability

The system architecture should support automated testing of:

- ASP.NET Core backend functionality.
- Database-related behaviour.
- React functionality.
- Flutter functionality.
- Agentic AI workflow behaviour.
- Validation and failure scenarios.
- End-to-end integration flows.

Continuous Integration should automatically perform suitable build, analysis, and test operations when code changes are pushed to configured branches.

## 8. System Architecture

SnapSync AI follows a multi-layer full-stack architecture in which the React web application and Flutter mobile application communicate with a common ASP.NET Core Web API.

The ASP.NET Core backend acts as the authoritative application layer. It handles authentication, authorization, business rules, validation, database operations, booking logic, and communication with the Agentic AI service.

The high-level application architecture is:

React Web Application
        ↓
ASP.NET Core Web API
        ↓
PostgreSQL Database
        ↑
Flutter Mobile Application

Both client applications use the same backend API and business rules. The clients do not directly access the PostgreSQL database.

### 8.1 Web Architecture

The React application is mainly used by studio owners and administrators.

The web application communicates with the ASP.NET Core REST API for operations such as:

- Authentication
- Studio profile management
- Portfolio management
- Service and package management
- Availability management
- Booking management
- Administration
- AI proposal review and approval

### 8.2 Mobile Architecture

The Flutter application is mainly used by customers.

The mobile application communicates with the same ASP.NET Core API for:

- Authentication
- Studio discovery
- Viewing studio portfolios
- Viewing services and packages
- Package customization
- Booking creation
- Booking tracking
- Reviews
- AI-assisted recommendations

This ensures that both web and mobile applications use the same authoritative business logic.

### 8.3 Backend Architecture

ASP.NET Core is the central application backend.

It is responsible for:

- REST API endpoints
- Authentication and authorization
- Role-based access control
- Business rule validation
- Server-side pricing
- Studio and package validation
- Availability validation
- Booking conflict detection
- PostgreSQL database access
- AI workflow persistence
- Human approval operations
- Communication with the internal Python AI service

Important business operations are validated by ASP.NET Core instead of trusting values provided by client applications or AI-generated output.

### 8.4 Database Architecture

PostgreSQL is used as the authoritative relational database.

It stores information related to:

- Users
- Studios
- Studio portfolios
- Services and packages
- Studio availability
- Bookings
- Booking history
- Customers
- Reviews
- AI workflows
- AI workflow events
- AI workflow approvals

Database access is performed through the ASP.NET Core backend.

### 8.5 Agentic AI Architecture

The Agentic AI subsystem is implemented as an internal Python service.

The AI architecture is:

Flutter / React
      ↓
ASP.NET Core API
      ↓
FastAPI
      ↓
LangGraph
      ↓
Gemini

The client applications never communicate directly with Gemini or the Python AI service.

FastAPI exposes the internal AI workflow interface, while LangGraph coordinates the multi-step Agentic AI process.

The workflow contains four specialized agents:

1. Studio Matching Agent
2. Package Recommendation Agent
3. Scheduling Agent
4. Validation and Safety Agent

The AI generates recommendations, while ASP.NET Core performs deterministic validation and remains responsible for authoritative business operations.

### 8.6 Human-in-the-Loop Architecture

AI-generated proposals are not automatically converted into bookings.

After the AI workflow produces a valid recommendation, the proposal can enter an `AwaitingApproval` state.

An authorized studio owner or administrator can then review the proposal through the React application and approve or reject it.

Before approval is accepted, ASP.NET Core performs fresh deterministic validation of important information such as pricing, package status, services, availability, and booking conflicts.

This architecture ensures that AI assists the decision-making process without receiving unrestricted control over business operations.

### 8.7 Location Integration

The system supports location-based studio information using latitude and longitude coordinates.

Studio owners can maintain studio location information, while customer-facing functionality can use location information to assist with nearby studio discovery and distance-related operations.

Location and distance calculations are treated as supporting information and are validated through the application backend where required.


## 9. Technology Stack

SnapSync AI uses multiple technologies selected according to the responsibilities of each system layer.

### 9.1 ASP.NET Core (.NET 8)

ASP.NET Core is used to implement the main REST API.

It provides:

- API endpoints
- Authentication and authorization
- Business logic
- Validation
- Database communication
- Booking operations
- AI workflow persistence
- Integration with the internal Python AI service

ASP.NET Core remains the authoritative backend for the complete system.

### 9.2 React and Vite

React is used to develop the web application.

Vite is used as the frontend development and build tool.

The React application mainly supports studio owners and administrators through interfaces for studio management, bookings, administration, and AI proposal review.

### 9.3 Flutter

Flutter is used to develop the customer-facing mobile application.

It provides functionality for:

- Studio browsing
- Package selection
- Booking
- Booking tracking
- Reviews
- AI recommendation requests
- Mobile location functionality

The Flutter application communicates with the ASP.NET Core REST API.

### 9.4 PostgreSQL

PostgreSQL is used as the relational database management system.

It stores authoritative application data including user, studio, package, booking, review, and Agentic AI workflow information.

### 9.5 Python and FastAPI

Python is used for the Agentic AI subsystem.

FastAPI provides the internal service interface used by ASP.NET Core to execute AI workflows.

The Python service does not directly manage authoritative application database records.

### 9.6 LangGraph

LangGraph is used to orchestrate the multi-step Agentic AI workflow.

It coordinates the execution of the four specialized agents and allows workflow state to move through the required AI stages in a controlled manner.

### 9.7 Gemini

Gemini is used as the Large Language Model for AI reasoning and recommendation generation.

Gemini assists the specialized agents, while important business facts such as pricing, availability, authorization, and booking conflicts remain subject to deterministic backend validation.

### 9.8 Google Maps and Device Location

Location-related functionality is used to support studio location selection, customer location information, nearby studio discovery, and distance-related features.

The web application supports studio location selection, while the Flutter application can use device location functionality for customer-side location features.

### 9.9 Git and GitHub

Git is used for source code version control, while GitHub is used for repository hosting and team collaboration.

Separate branches are used by team members to develop their assigned components before integration.

### 9.10 GitHub Actions

GitHub Actions is used for Continuous Integration.

The CI workflow automatically validates the major technologies in the project by performing:

- ASP.NET Core restore and build
- React dependency installation and production build
- Flutter dependency installation, analysis, and tests
- Python dependency installation and Agentic AI tests

This provides automated verification when configured repository events occur.

## 10. System Components

SnapSync AI is divided into four major functional components. Each component is responsible for a specific part of the photography booking process while sharing the same ASP.NET Core backend and PostgreSQL database.

### 10.1 Studio & Portfolio Management

The Studio & Portfolio Management component manages the information required to represent photography studios within the platform.

The main functions include:

- Creating and updating studio profiles.
- Managing studio contact and business information.
- Managing studio location information.
- Maintaining latitude and longitude coordinates.
- Managing studio portfolio albums and images.
- Managing photography services offered by the studio.
- Managing studio availability.
- Providing public studio information for customer applications.
- Supporting location-based studio discovery.

Studio owners manage these functions mainly through the React web application, while customers can view relevant studio information through the Flutter mobile application.

This component also supports the Studio Matching Agent by providing verified studio information that can be used when identifying suitable studios for a customer's photography requirements.


### 10.2 Package & Service Management

The Package & Service Management component handles the photography packages and services offered to customers.

The main functions include:

- Creating and managing photography packages.
- Managing included photography services.
- Maintaining base package prices.
- Maintaining package duration.
- Supporting additional services and customization.
- Supporting extra coverage hours.
- Supporting additional photographer options where applicable.
- Displaying package information to customers.
- Calculating final package-related pricing using backend-controlled information.

The final price can be calculated using relevant package configuration such as:

**Final Price = Base Price + Add-ons + Extra Hours + Additional Photographer Charges**

Authoritative pricing is calculated or validated by the backend instead of trusting values submitted by the client application.

This component provides information used by the Package Recommendation Agent when identifying a package that matches customer requirements and budget.


### 10.3 Booking & Scheduling Management

The Booking & Scheduling Management component manages the booking lifecycle between customers and photography studios.

The main functions include:

- Creating customer bookings.
- Selecting the required studio and package.
- Selecting booking dates and times.
- Validating studio availability.
- Detecting overlapping or conflicting bookings.
- Performing server-side pricing validation.
- Maintaining booking status.
- Maintaining booking status history.
- Allowing customers to view their bookings.
- Allowing authorized studio owners to manage relevant bookings.
- Recording important booking changes.

Customer identity is obtained from the authenticated user context rather than being trusted directly from client-submitted values.

Before relevant booking operations are accepted, the backend validates important information such as studio ownership, package information, availability, and booking conflicts.

This component also provides scheduling information to the Scheduling Agent.


### 10.4 Customer & Review Management

The Customer & Review Management component manages customer-related information and feedback within the platform.

The main functions include:

- Managing customer-related information.
- Providing customers with access to their relevant system information.
- Supporting customer booking interactions.
- Allowing eligible customers to submit reviews.
- Recording customer ratings and feedback.
- Displaying relevant review information.
- Allowing administrators to monitor reviews.
- Applying validation to review-related operations.

Customer feedback helps provide information about experiences with photography studios and services.

The component is integrated with the rest of the platform so that customer and review operations use the same authentication, authorization, and backend validation mechanisms.


### 10.5 Component Integration

Although the system is divided into four major components, they operate as one integrated platform.

A typical customer flow can move through the components as follows:

**Find Studio → Choose Package → Create Booking → Complete Service → Submit Review**

The Agentic AI workflow supports this process through:

**Studio Matching → Package Recommendation → Scheduling → Validation**

The four components share:

- ASP.NET Core REST API
- PostgreSQL database
- Authentication and authorization
- Common business rules
- React and Flutter integration
- Agentic AI workflow integration

This prevents each component from operating as an isolated application and allows SnapSync AI to provide one complete photography booking workflow.

### 10.1 Studio & Portfolio Management
### 10.2 Package & Service Management
### 10.3 Booking & Scheduling Management
### 10.4 Customer & Review Management

## 11. Web Application – React

SnapSync AI uses React with Vite for the web application. The web interface is mainly designed for Studio Owners and Administrators.

### 11.1 Studio Owner Functions

The studio owner interface provides features for:

- Studio dashboard
- Studio profile management
- Portfolio and album management
- Photography service management
- Package-related management
- Studio availability management
- Booking management
- AI recommendation review
- AI proposal approval and rejection

Protected routes are used to restrict studio management functions to authenticated and authorized users.

### 11.2 Administrator Functions

The administrator interface provides:

- Admin dashboard
- Studio management
- Customer management
- Booking monitoring
- Review monitoring
- Reporting
- Administrator profile management

Administrative API operations are protected using role-based authorization.

### 11.3 API Communication

The React application communicates with the ASP.NET Core backend through REST API requests.

The frontend is responsible for presenting information and collecting user input, while authoritative validation and important business rules remain in the backend.


## 12. Mobile Application – Flutter

SnapSync AI uses Flutter for the customer-facing mobile application.

The mobile application provides an integrated customer journey from studio discovery to booking and review.

### 12.1 Customer Flow

The main customer flow includes:

Login / Registration  
→ Home  
→ Browse Studios  
→ Studio Details  
→ Portfolio / Services / Availability  
→ Packages  
→ Package Details  
→ Customize Package  
→ Select Date and Time  
→ Booking Summary  
→ Confirm Booking  
→ My Bookings  
→ Booking Details  
→ Review

### 12.2 AI Recommendation Flow

Customers can also request AI assistance through the Flutter application.

The customer provides requirements such as:

- Photography type
- Preferred location
- Maximum budget
- Required date range
- Coverage duration
- Requested services

The request is sent to ASP.NET Core, which coordinates the Agentic AI workflow.

Customers can view the status of their AI recommendation and refresh the workflow information when required.

### 12.3 Device Location

Flutter supports device location functionality for customer-side location features.

Location permission is requested when required rather than being unnecessarily requested for unrelated application functions.

Customer location can be used to support nearby studio discovery and distance-related functionality.


## 13. Backend – ASP.NET Core

SnapSync AI uses ASP.NET Core .NET 8 as the central and authoritative backend.

Both React and Flutter applications communicate with the same backend.

### 13.1 REST API

The backend exposes REST APIs for the major system areas, including:

- Authentication
- Users
- Studios
- Portfolios
- Services and packages
- Availability
- Bookings
- Reviews
- Administration
- Agentic AI workflows

### 13.2 Authentication and Authorization

Protected API operations require authenticated users.

Role-based authorization is used to control operations available to:

- Customers
- Studio Owners
- Administrators

For sensitive operations, the backend derives user identity from the authenticated context instead of trusting identity values submitted by the client.

### 13.3 Business Rule Validation

ASP.NET Core performs authoritative validation for important operations.

Examples include:

- Package and service validation
- Server-side pricing
- Studio ownership
- Studio availability
- Booking conflicts
- Booking status operations
- AI proposal validation
- Human approval authorization

This prevents React, Flutter, or AI-generated information from bypassing core business rules.

### 13.4 Agentic AI Integration

ASP.NET Core communicates with the internal Python FastAPI service for Agentic AI execution.

The backend first creates a durable workflow record and then requests AI execution through the protected internal service.

After AI processing, ASP.NET Core validates the result before publishing an authoritative proposal.

If the AI service fails, the system follows a safe failure process and does not create a partial booking.


## 14. Database – PostgreSQL

PostgreSQL is used as the relational database for SnapSync AI.

The database provides persistent storage for the application's authoritative data.

### 14.1 Main Data Areas

The database contains information related to:

- Users
- Studios
- Studio portfolios
- Studio services
- Packages
- Studio availability
- Bookings
- Booking history
- Reviews
- AI workflows
- AI workflow events
- AI workflow approvals

### 14.2 Data Integrity

Database constraints and backend validation are used together to maintain valid system data.

Examples include:

- Required relationships
- Valid identifiers
- Location coordinate validation
- Workflow state restrictions
- Booking relationships
- Authorization-based ownership checks

### 14.3 AI Workflow Persistence

Agentic AI workflow information is persisted using dedicated workflow data structures.

`AiWorkflows` maintains the current durable workflow state.

`AiWorkflowEvents` maintains an audit trail of important workflow events.

`AiWorkflowApprovals` maintains information related to human approval and rejection.

The Python AI service does not directly modify these PostgreSQL records. Persistence is controlled through ASP.NET Core.

### 14.4 Database Security

Database credentials are not intended to be stored directly in source-controlled production configuration.

Deployment-specific credentials and sensitive configuration are supplied using secure configuration mechanisms such as environment variables.

Client applications do not connect directly to PostgreSQL.

## 15. Agentic AI Implementation

SnapSync AI includes an Agentic AI subsystem that assists customers in identifying a suitable studio, selecting an appropriate photography package, finding a suitable schedule, and validating the generated recommendation.

The Agentic AI subsystem is implemented using Python, FastAPI, LangGraph, and Gemini.

The overall interaction follows:

Customer Request  
→ ASP.NET Core  
→ Agentic AI Workflow  
→ Studio Matching  
→ Package Recommendation  
→ Scheduling  
→ Validation & Safety  
→ ASP.NET Core Revalidation  
→ Human Review

The AI subsystem acts as a recommendation and reasoning layer. It does not directly create bookings, modify authoritative pricing, or directly access the PostgreSQL database.

### 15.1 Studio Matching Agent

The Studio Matching Agent is responsible for identifying photography studios that are relevant to the customer's requirements.

The agent considers information such as:

- Photography type
- Customer's preferred location
- Requested services
- Budget-related requirements
- Available studio information

Authoritative studio information is obtained through controlled application data rather than allowing the AI model to invent studio records.

The output of this stage is passed to the next stage of the Agentic AI workflow.

If a suitable studio cannot be identified or the workflow cannot safely continue, the system can terminate the recommendation process without creating a booking.

### 15.2 Package Recommendation Agent

After a suitable studio has been identified, the Package Recommendation Agent evaluates the available package and service information.

The agent considers information such as:

- Customer budget
- Requested photography services
- Required coverage duration
- Package duration
- Base package price
- Additional service requirements
- Extra-hour requirements
- Additional photographer requirements where applicable

The AI assists in selecting an appropriate option, but it is not treated as the authoritative source for package prices.

Package identifiers, services, pricing, and other important information are subsequently validated by the ASP.NET Core backend.

This separation allows Gemini to assist with recommendation reasoning while deterministic business rules remain under application control.

### 15.3 Scheduling Agent

The Scheduling Agent is responsible for identifying suitable scheduling options based on the customer's requested photography period and the selected studio.

The agent considers information such as:

- Customer's requested date range
- Preferred start and end times when provided
- Required coverage duration
- Studio availability
- Selected studio and package information

The Scheduling Agent does not independently reserve a time slot or create a booking.

Scheduling suggestions are treated as recommendations and are later checked against authoritative availability and booking information by the ASP.NET Core backend.

This prevents an AI-generated schedule from bypassing current studio availability or existing booking conflicts.


### 15.4 Validation & Safety Agent

The Validation & Safety Agent is the final AI stage before a recommendation is prepared for human review.

Its responsibility is to examine the combined output produced by the previous agents and determine whether the recommendation is sufficiently complete and consistent to continue.

The validation process considers information produced by:

- Studio Matching Agent
- Package Recommendation Agent
- Scheduling Agent

The agent helps identify missing, inconsistent, or unsuitable recommendation information.

However, AI-based validation is not used as a replacement for deterministic backend validation.

ASP.NET Core performs authoritative checks for important business information such as:

- Studio existence and active status
- Package validity
- Service validity
- Pricing
- Coverage duration
- Studio availability
- Existing booking conflicts
- User authorization

If the recommendation cannot be safely completed, the workflow can terminate in an appropriate safe state instead of creating a booking.


### 15.5 Human Approval Workflow

SnapSync AI uses a human-in-the-loop approach for AI-generated recommendations.

After the Agentic AI stages are completed and the recommendation passes the required backend validation, an authoritative proposal can be persisted and presented for human review.

The workflow can progress through stages similar to:

Submitted  
→ Studio Matching  
→ Package Recommendation  
→ Scheduling  
→ Validation  
→ Awaiting Approval  
→ Approved / Rejected

An authorized Studio Owner or Administrator can review the generated proposal through the web application.

The reviewer can:

- View the AI-generated recommendation.
- Review the selected studio and package information.
- Review scheduling information.
- Approve the proposal.
- Reject the proposal with an appropriate reason.

Proposal versioning is used to reduce the risk of acting on an outdated AI recommendation.

Before an approval is accepted, ASP.NET Core performs fresh deterministic revalidation. This can include checking:

- Current studio status
- Current package information
- Current pricing
- Required services
- Availability
- Booking conflicts
- Coverage requirements

If the information has become outdated or invalid, the workflow can move to a `RevalidationRequired` state instead of accepting the stale recommendation.

Approval of an AI recommendation does not itself bypass the normal booking process. Final booking operations remain subject to the application's normal backend validation.


### 15.6 Workflow Persistence and Auditability

The Agentic AI workflow uses durable persistence rather than depending only on temporary Python memory.

The main persistent AI workflow data includes:

- `AiWorkflows`
- `AiWorkflowEvents`
- `AiWorkflowApprovals`

Workflow events provide an audit trail that can be used to understand important state transitions and investigate failures.

ASP.NET Core owns the canonical persisted workflow state. The Python service does not directly modify the PostgreSQL database.


### 15.7 Structured Communication

Communication between ASP.NET Core and the Python Agentic AI service uses structured request and response data.

This allows the backend to validate AI results before they are accepted as an application proposal.

The Python service is accessed through an internal FastAPI endpoint protected using internal service authentication.

React and Flutter clients do not have access to this internal token and do not communicate directly with the Python service.


### 15.8 Safe Failure Handling

External AI services may occasionally be unavailable or fail to produce a usable recommendation.

SnapSync AI is designed to fail safely in these situations.

When an AI workflow cannot be completed safely:

- The system does not create a partial booking.
- The failure can be recorded in the workflow state and audit history.
- The customer can be informed that the recommendation was not completed.
- Existing authoritative booking information remains unchanged.

This design prevents an AI provider failure from causing an incomplete or unauthorized business transaction.
## 16. Third-Party Service Integration

SnapSync AI integrates external services to support location-based functionality and intelligent recommendation generation.

### 16.1 Google Maps Integration

Google Maps functionality is used to support studio location management and location-based photography studio discovery.

The React web application allows a Studio Owner to maintain the geographical location of the studio. Latitude and longitude coordinates are stored with the studio information and can be used by the backend for location-related operations.

The location functionality supports:

- Studio location selection.
- Latitude and longitude storage.
- Location-based studio information.
- Nearby studio discovery.
- Distance-related calculations.

Studio coordinates are validated before being stored to reduce the possibility of invalid geographical information.

### 16.2 Mobile Device Location

The Flutter application can access the customer's device location using location services.

Location permission is requested when the customer uses functionality that requires the current location.

The customer's location can be used to support nearby studio discovery. Distance between the customer and available studios can then be used as supporting information when presenting suitable studios.

If location permission is unavailable or denied, the application should continue to provide appropriate non-location functionality rather than making the complete application dependent on GPS access.

### 16.3 Gemini API Integration

Gemini is integrated as the Large Language Model used by the Agentic AI subsystem.

The Gemini API is accessed only from the server-side Python service.

The API key is not exposed to:

- React application
- Flutter application
- Public ASP.NET Core API responses

Gemini supports reasoning and recommendation generation for the specialized AI agents.

However, Gemini output is not considered authoritative business data. Important information such as studio identifiers, package information, pricing, availability, booking conflicts, and authorization is validated through controlled application logic.

### 16.4 External Service Failure Handling

Third-party services can become temporarily unavailable or return errors.

The system is therefore designed so that external service failures do not directly create invalid business transactions.

For Agentic AI operations, a provider failure results in safe workflow handling without automatically creating a booking.

For location-related functionality, the application should provide suitable fallback behaviour when device location or external map functionality is unavailable.


## 17. Security and Authentication

Security is applied across the web application, mobile application, backend, database, and Agentic AI integration.

### 17.1 Authentication

SnapSync AI uses backend-controlled authentication for protected application functionality.

After successful authentication, the user's authenticated identity is used by ASP.NET Core when processing protected requests.

JWT-based authentication is used for communication with protected API endpoints.

The same backend authentication mechanism supports both React and Flutter clients.

### 17.2 Role-Based Authorization

The platform contains different permissions for:

- Customer
- Studio Owner
- Administrator

ASP.NET Core performs role-based authorization before allowing access to protected operations.

For example:

- Customers can access their relevant booking and AI recommendation operations.
- Studio Owners can manage information associated with their studios.
- Authorized Studio Owners can review relevant AI proposals.
- Administrators can access administrative operations.

Authorization is enforced by the backend rather than relying only on hidden frontend controls.

### 17.3 Authenticated Identity

Sensitive operations do not rely on a client application to provide an authoritative user identity.

Where required, the backend derives the user identifier and role from the authenticated security context.

This reduces the risk of one user attempting to perform an operation using another user's identifier.

### 17.4 Server-Side Validation

Important business information is validated by ASP.NET Core.

Examples include:

- Studio ownership
- Package validity
- Service validity
- Pricing
- Availability
- Booking conflicts
- AI proposal versions
- Human approval permissions

Frontend validation is used to improve user experience, but it does not replace backend validation.

### 17.5 Secret Management

Sensitive credentials must not be stored directly in source-controlled application configuration.

Sensitive information includes:

- PostgreSQL credentials
- JWT signing keys
- Gemini API keys
- Internal AI workflow tokens

Local or deployment-specific secure configuration and environment variables are used to provide these values.

Example configuration names include:

- `ConnectionStrings__DefaultConnection`
- `Jwt__Key`
- `GEMINI_API_KEY`
- `INTERNAL_WORKFLOW_TOKEN`
- `AI_WORKFLOW_PYTHON_BASE_URL`

Actual secret values must never be included in project documentation or committed to the public/shared source repository.

### 17.6 Internal AI Service Security

The Python FastAPI Agentic AI service is treated as an internal service.

React and Flutter do not directly call the internal AI execution endpoint.

Communication follows:

React / Flutter
→ ASP.NET Core
→ Internal FastAPI Service

ASP.NET Core authenticates internal workflow requests using an internal service token.

This prevents normal client applications from directly triggering protected internal AI execution operations.

### 17.7 Database Security

Client applications do not directly connect to PostgreSQL.

Database access is performed through the authoritative ASP.NET Core backend.

This allows authentication, authorization, validation, and business rules to be applied before database operations are performed.

### 17.8 AI Safety

AI-generated output is treated as a recommendation rather than automatically trusted application data.

The system applies several safety controls:

- Controlled AI workflow stages.
- Structured AI communication.
- Deterministic backend validation.
- Durable workflow state.
- Human approval.
- Proposal version checking.
- Fresh validation before approval.
- Safe failure handling.

The AI service cannot directly create a booking or bypass the normal backend booking rules.

### 17.9 Secure Development Practices

The project follows secure development practices including:

- Keeping runtime secrets out of Git.
- Ignoring local configuration files containing sensitive values.
- Keeping runtime-uploaded files out of source control where appropriate.
- Performing backend authorization checks.
- Using server-side validation for important business operations.
- Using Continuous Integration to verify project builds and automated tests.

## 18. Testing and Quality Assurance

## 19. Continuous Integration

SnapSync AI uses GitHub Actions to provide Continuous Integration (CI) for the major technologies used in the project.

The CI workflow is defined in:

`.github/workflows/ci.yml`

The workflow automatically verifies the project when configured GitHub push and pull request events occur.

### 19.1 ASP.NET Core CI

The backend CI job:

- Sets up .NET 8.
- Restores project dependencies.
- Builds the ASP.NET Core project.
- Detects backend compilation errors before integration.

### 19.2 React CI

The frontend CI job:

- Sets up Node.js.
- Installs dependencies using `npm ci`.
- Creates a production build of the React application.
- Detects dependency and build-related problems.

### 19.3 Flutter CI

The Flutter CI job:

- Sets up Flutter.
- Installs Flutter dependencies.
- Runs Flutter static analysis.
- Runs automated Flutter tests.

Warnings and informational analyzer messages are handled separately from actual compilation errors so that existing non-critical analyzer messages do not incorrectly represent a failed build.

### 19.4 Agentic AI CI

The Agentic AI CI job:

- Sets up Python.
- Installs dependencies from `requirements.txt`.
- Executes the Python automated test suite using pytest.
- Verifies important Agentic AI implementation behaviour without requiring a live customer booking operation.

### 19.5 CI Result

The GitHub Actions workflow was executed successfully after being pushed to the project repository.

All four CI jobs completed successfully:

- ASP.NET Core Build – Passed
- React Build – Passed
- Flutter Analyze and Test – Passed
- Python Agentic AI Tests – Passed

This provides automated evidence that the main project components can be built and tested together within the configured CI environment.

The successful GitHub Actions execution can be included as evidence in the final project documentation and demonstration.

## 20. Deployment

SnapSync AI is designed as a multi-service application in which the frontend, backend, database, and Agentic AI components can be deployed independently while operating as one integrated system.

The planned deployment architecture is:

React Web Application
        ↓
ASP.NET Core Web API
        ↓
PostgreSQL Database
        ↓
Internal Python FastAPI Service
        ↓
LangGraph
        ↓
Gemini API

The Flutter mobile application communicates with the same deployed ASP.NET Core API.

### 20.1 Backend Deployment

The ASP.NET Core Web API will be deployed as the main public backend service.

Deployment configuration must provide required environment-specific values such as:

- PostgreSQL connection string
- JWT configuration
- Internal AI service URL
- Internal workflow authentication token

Sensitive values must be provided through secure deployment configuration and must not be committed to Git.

### 20.2 Database Deployment

PostgreSQL will provide the persistent production database.

Before deployment, the required database schema and constraints must be verified against the deployed application version.

Database credentials must be supplied securely through the deployment environment.

### 20.3 React Deployment

The React application will be built using the production build process and deployed as the web interface for Studio Owners and Administrators.

The deployed frontend will communicate with the deployed ASP.NET Core API rather than using local development URLs.

### 20.4 Agentic AI Deployment

The Python FastAPI service will be deployed as an internal service used by ASP.NET Core.

The deployment environment must provide:

- Gemini API configuration
- Internal workflow token
- ASP.NET Core API configuration
- Required Python dependencies

The FastAPI service should not be exposed as a normal customer-facing API.

### 20.5 Flutter Distribution

A release build of the Flutter mobile application will be generated for project demonstration and assessment.

The mobile application must use the deployed ASP.NET Core API endpoint rather than the local development backend address.

The final deliverable should include the required Flutter APK.

### 20.6 Deployment Verification

After deployment, the following areas will be verified:

- React application availability
- ASP.NET Core API availability
- PostgreSQL connectivity
- Authentication
- Main application API operations
- Internal ASP.NET Core to FastAPI communication
- Environment configuration
- Flutter communication with the deployed API
- Relevant third-party integrations

### 20.7 Current Status

Continuous Integration has been configured and successfully executed for the major project components.

Final production deployment and Flutter release APK generation remain part of the final project preparation and will be updated in this section after deployment verification is completed.

## 21. Individual Contributions

## 22. AI Usage and Reflection

Artificial Intelligence was used in this project in two different ways: as a core feature of the SnapSync AI platform and as a supporting tool during the software development process.

### 22.1 AI as a System Feature

SnapSync AI integrates Agentic AI to assist customers during the photography booking process. The AI workflow is implemented using Python, FastAPI, LangGraph, and the Gemini API.

The workflow contains four specialized agents:

1. Studio Matching Agent – identifies suitable studios based on customer requirements.
2. Package Recommendation Agent – recommends suitable photography packages and services.
3. Scheduling Agent – suggests suitable scheduling options based on the request and available information.
4. Validation & Safety Agent – checks the generated recommendation before it is presented for human review.

The AI does not directly create or modify bookings. Important business information such as studio data, package prices, services, availability, and booking conflicts is validated by the ASP.NET Core backend.

A human approval stage is included so that AI-generated recommendations can be reviewed before further booking actions are performed.

### 22.2 AI Tools Used During Development

AI-assisted development tools were used as supporting resources during the development of the project. They assisted with activities such as:

- Understanding implementation approaches.
- Generating initial code suggestions.
- Identifying possible causes of errors.
- Reviewing implementation logic.
- Suggesting test cases.
- Improving documentation structure.
- Assisting with debugging and integration issues.

AI-generated suggestions were not treated as automatically correct. Generated code and recommendations were reviewed against the project requirements and existing architecture before being used.

Where necessary, the team modified or rejected AI-generated suggestions to ensure that the final implementation remained compatible with the system design and business requirements.

### 22.3 Human Verification of AI-Assisted Work

Human verification remained an important part of the development process.

The team used techniques such as:

- Reviewing generated source code.
- Building the affected applications.
- Running automated tests.
- Checking API behaviour.
- Verifying database changes before applying them.
- Reviewing security-sensitive configuration.
- Comparing generated solutions with project requirements.
- Performing manual integration checks.

This approach allowed AI tools to improve development productivity without replacing developer responsibility.

### 22.4 Reflection

AI-assisted development was useful for accelerating repetitive tasks, exploring implementation approaches, debugging problems, and improving documentation. However, the project also demonstrated that AI output must be verified carefully.

AI-generated solutions can contain incorrect assumptions, incompatible code, or suggestions that do not fully match the existing system architecture. External AI services may also experience temporary availability problems.

Therefore, the team treated AI as an assistant rather than the final decision-maker. Deterministic backend validation, testing, human review, and controlled approval were maintained for important system operations.

This experience demonstrated that AI can improve software development and user-facing workflows when it is combined with clear system boundaries, validation, security controls, and human oversight.

## 23. Challenges and Limitations
## 23. Challenges and Limitations

During the development and integration of SnapSync AI, the team encountered several technical and integration challenges. These challenges provided practical experience in managing a full-stack system containing web, mobile, backend, database, third-party services, and Agentic AI components.

### 23.1 Database Schema Integration

One of the major challenges was maintaining consistency between the ASP.NET Core application models and the PostgreSQL database schema.

During integration, some required tables, columns, and constraints were not available in the existing database because different components had evolved during development.

To address this, the database was carefully inspected and reconciled while protecting existing development data. Database backups and verification steps were used before applying important schema changes.

### 23.2 Integration of Multiple Technologies

SnapSync AI combines several technologies, including React, Flutter, ASP.NET Core, PostgreSQL, Python FastAPI, LangGraph, Gemini, and external location services.

Maintaining consistent communication between these technologies required careful API contract design, environment configuration, authentication, and error handling.

### 23.3 Agentic AI Service Availability

The Agentic AI workflow depends on an external Gemini service for LLM-based reasoning.

During live integration testing, temporary provider-side errors such as HTTP 503 and 504 responses were encountered. Retry and safe-failure mechanisms were therefore important parts of the AI integration.

The system is designed to fail safely without creating a booking when the AI workflow cannot complete successfully.

### 23.4 AI Reliability and Validation

LLM-generated responses cannot be considered authoritative business data.

Therefore, important information such as package prices, studio availability, service information, and booking conflicts must be validated by deterministic backend logic.

The AI is used for recommendation and reasoning, while ASP.NET Core remains responsible for authoritative business validation.

### 23.5 Multi-Service Configuration

The system requires multiple services to operate together during development, including:

- PostgreSQL
- ASP.NET Core API
- Python FastAPI service
- React application
- Flutter application

Managing ports, environment variables, internal service URLs, authentication tokens, and API endpoints across these services increased integration complexity.

### 23.6 Third-Party Service Dependency

Location functionality and AI functionality depend on external services.

Google Maps functionality requires correct API configuration, while Agentic AI depends on the availability of the Gemini service.

Therefore, some functionality may be affected by network availability, provider availability, API configuration, or external service limitations.

### 23.7 Current Limitations

At the current stage of development, some final verification activities are still pending.

These include:

- Final successful live end-to-end verification of the complete Agentic AI workflow.
- Final production deployment verification.
- Generation and verification of the Flutter release APK.
- Complete system-level testing, including performance, security, AI evaluation, and failure-recovery testing.
- Final verification of third-party services in the deployed environment.

These items are treated as remaining project preparation activities and should not be considered completed until they have been verified with appropriate evidence.

### 23.8 Lessons Learned

The project demonstrated the importance of maintaining clear boundaries between AI-generated recommendations and authoritative business operations.

It also highlighted the importance of database consistency, secure configuration management, automated CI checks, deterministic validation, human approval, and safe failure handling when integrating AI into a full-stack application.


## 24. Future Improvements

Although SnapSync AI provides the core functionality required for an intelligent photography booking and management platform, several improvements can be considered for future versions.

### 24.1 Improved AI Recommendation Accuracy

The Agentic AI workflow can be improved using additional customer preferences and historical interaction data. Future versions could provide more personalized studio, package, and scheduling recommendations while continuing to validate important business information through the backend.

### 24.2 Improved AI Provider Resilience

Additional resilience mechanisms could be introduced to reduce the impact of temporary external AI service failures. This may include improved retry strategies, monitoring, fallback mechanisms, and better workflow recovery.

### 24.3 Advanced Search and Recommendation

Studio discovery could be enhanced using additional criteria such as ratings, price range, photography style, distance, availability, services, and previous customer feedback.

### 24.4 Real-Time Notifications

Future versions could introduce push notifications for important events such as:

- Booking confirmations
- Booking status changes
- Upcoming photography sessions
- AI recommendation approval or rejection
- Review reminders

### 24.5 Payment Integration

A secure online payment gateway could be integrated to support deposits, full payments, payment confirmation, and refund-related workflows.

### 24.6 Enhanced Analytics

More advanced dashboards could be introduced for Studio Owners and Administrators to analyse booking trends, popular packages, revenue, customer activity, studio performance, and review statistics.

### 24.7 Improved Workflow Idempotency

Future development could introduce persistent idempotency support for important operations. This would provide additional protection against accidental duplicate requests caused by retries, network interruptions, or repeated user actions.

### 24.8 Monitoring and Observability

Centralized logging, application monitoring, performance metrics, and alerting could be introduced for the ASP.NET Core API, database, and Agentic AI services.

This would make production issues easier to identify and diagnose.

### 24.9 Cloud Scalability

The system could be extended with containerization and cloud-based deployment strategies to support increased numbers of customers, studios, bookings, and AI workflow requests.

### 24.10 User Experience Improvements

Future versions could further improve accessibility, responsive design, mobile usability, loading behaviour, offline handling, and user guidance throughout the booking process.

Overall, these improvements would help SnapSync AI become more scalable, reliable, personalized, and suitable for wider real-world adoption.

## 25. Conclusion


SnapSync AI was developed as an intelligent photography booking and management platform that integrates studio management, package and service management, booking and scheduling, and customer and review management within a single system.

The platform uses React for the web application, Flutter for the mobile application, ASP.NET Core for the main backend API, and PostgreSQL for persistent data management. Agentic AI is integrated using Python, FastAPI, LangGraph, and Gemini through four specialized agents: Studio Matching, Package Recommendation, Scheduling, and Validation & Safety.

A key design principle of the project is that AI provides recommendations rather than directly controlling important business operations. The ASP.NET Core backend remains responsible for authoritative validation, while human approval is included for AI-generated recommendations before further booking actions are performed.

The project also demonstrates the integration of web, mobile, backend, database, third-party services, Agentic AI, authentication, role-based authorization, secure configuration, and continuous integration within one full-stack solution.

Overall, SnapSync AI demonstrates how Agentic AI can support and simplify the photography booking process while maintaining deterministic validation, security, auditability, and human oversight. Final system testing, deployment verification, and release preparation will be completed as part of the remaining project activities.

## 26. References

The following official documentation and technical resources were referred to during the design and development of SnapSync AI.

1. Microsoft, “ASP.NET Core Documentation,” Microsoft Learn.
   https://learn.microsoft.com/aspnet/core/

2. React, “React Documentation.”
   https://react.dev/

3. Flutter, “Flutter Documentation.”
   https://docs.flutter.dev/

4. PostgreSQL Global Development Group, “PostgreSQL Documentation.”
   https://www.postgresql.org/docs/

5. FastAPI, “FastAPI Documentation.”
   https://fastapi.tiangolo.com/

6. LangChain, “LangGraph Documentation.”
   https://docs.langchain.com/oss/python/langgraph/

7. Google, “Gemini API Documentation.”
   https://ai.google.dev/gemini-api/docs/

8. Google, “Google Maps Platform – Maps JavaScript API Documentation.”
   https://developers.google.com/maps/documentation/javascript

9. GitHub, “GitHub Actions Documentation.”
   https://docs.github.com/actions

10. Microsoft, “.NET Documentation,” Microsoft Learn.
    https://learn.microsoft.com/dotnet/

## 27. Appendices

The appendices provide supporting evidence for the design, implementation, integration, testing, and development process of the SnapSync AI system.

### Appendix A – System Architecture

Include the final system architecture diagram showing the communication between:

- React Web Application
- Flutter Mobile Application
- ASP.NET Core Web API
- PostgreSQL Database
- Python FastAPI Service
- LangGraph Agentic AI Workflow
- Gemini API
- Google Maps / Location Services

### Appendix B – Database Design

Include:

- Entity Relationship Diagram (ERD)
- Main database tables
- Important relationships
- AI workflow persistence tables
- Relevant database constraints

### Appendix C – Web Application Screenshots

Include important React application screenshots such as:

- Login / Authentication
- Studio Dashboard
- Studio Profile Management
- Portfolio Management
- Service / Package Management
- Availability Management
- Booking Management
- AI Recommendation Review
- Admin Dashboard

### Appendix D – Mobile Application Screenshots

Include important Flutter application screenshots such as:

- Login / Registration
- Customer Home
- Studio Browsing
- Studio Details
- Portfolio
- Package Selection
- Booking Flow
- My Bookings
- Review Submission
- AI Recommendation Request
- AI Recommendation Status

### Appendix E – Agentic AI Workflow Evidence

Include evidence of the Agentic AI workflow:

Customer Request
→ Studio Matching Agent
→ Package Recommendation Agent
→ Scheduling Agent
→ Validation & Safety Agent
→ Human Approval

Supporting evidence may include:

- AI workflow screenshots
- Workflow status changes
- Structured AI outputs
- Human approval interface
- Safe failure handling
- Audit/event information

Only successfully verified results should be presented as completed workflow evidence. Failed or incomplete executions should be clearly identified as such.

### Appendix F – API Evidence

Include relevant API evidence such as:

- Swagger screenshots
- Authentication endpoints
- Studio endpoints
- Package and service endpoints
- Booking endpoints
- Review endpoints
- AI workflow endpoints
- Human approval endpoints

Sensitive authentication tokens, passwords, API keys, and other secrets must not be visible in screenshots.

### Appendix G – Continuous Integration Evidence

Include the GitHub Actions CI screenshot showing successful execution of:

- ASP.NET Core Build
- React Build
- Flutter Analyze and Test
- Python Agentic AI Tests

The successful CI execution can be used as evidence that the major project components were automatically checked through the repository workflow.

### Appendix H – Testing Evidence

This appendix will be completed after final system testing.

Evidence should include:

- Backend/API testing
- Database testing
- React testing
- Flutter testing
- End-to-end testing
- Performance testing
- Agentic AI evaluation
- Security and prompt-injection testing
- Failure and recovery testing

### Appendix I – Deployment Evidence

This appendix will be completed after final deployment.

Include:

- Deployed React application
- Deployed ASP.NET Core API
- Database connectivity evidence
- AI service deployment/configuration evidence
- API/Swagger verification
- Flutter APK evidence

### Appendix J – Git and Individual Contribution Evidence

Include:

- GitHub repository evidence
- Branch history
- Commit history
- Pull requests where applicable
- Individual contribution evidence
- Relevant implemented files or features

### Appendix K – Architecture Decision Records

The following Architecture Decision Records are maintained separately in the `docs/adr` directory:

- ADR 001 – React State Management
- ADR 002 – Flutter State Management
- ADR 003 – Agentic AI Orchestration
- ADR 004 – AI Workflow Persistence
- ADR 005 – Deployment Architecture

### Appendix L – AI Usage Evidence

Include the project AI usage log and supporting evidence where required.

The log should identify:

- Development task
- AI tool used
- Purpose of using the AI tool
- How the generated output was used or modified
- Human verification performed

Only actual AI usage should be documented.