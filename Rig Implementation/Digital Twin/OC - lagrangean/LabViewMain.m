% Main program
% Run Initialization file first

%%%%%%%%%%%%%%%%
% Get Variables
%%%%%%%%%%%%%%%%
% disturbances 
%valve opening [-] 
cv101 = P_vector(1);
cv102 = P_vector(2);
cv103 = P_vector(3);
% if value is [A] from 0.004 to 0.020
% if you want to convert to 0 (fully closed) to 1 (fully open)
% vo_n = (vo - 0.004)./(0.02 - 0.004);

%pump rotation [%]
pRate = P_vector(4);
% if value is [A] from 0.004 to 0.020
% if you want to convert to (min speed - max speed)
% goes from 12% of the max speed to 92% of the max speed
% pRate = 12 + (92 - 12)*(P_vector(4) - 0.004)./(0.02 - 0.004);

% always maintain the inputs greater than 0.5
% inputs computed in the previous MPC iteration
% Note that the inputs are the setpoints to the gas flowrate PID's
fic104sp = P_vector(5);
fic105sp = P_vector(6); 
fic106sp = P_vector(7);
%current inputs of the plant
u0old=[P_vector(5);P_vector(6);P_vector(7)];

% cropping the data vector
nd = size(I_vector,2);
dataCrop = (nd - BufferLength + 1):nd;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% MOST RECENT VALUE IS THE LAST ONE! %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% liquid flowrates [L/min]
fi101 = I_vector(1,dataCrop);
fi102 = I_vector(2,dataCrop);
fi103 = I_vector(3,dataCrop);

% actual gas flowrates [sL/min]
fic104 = I_vector(4,dataCrop);
fic105 = I_vector(5,dataCrop);
fic106 = I_vector(6,dataCrop);

% pressure @ injection point [mbar g]
pi105 = I_vector(7,dataCrop);
pi106 = I_vector(8,dataCrop);
pi107 = I_vector(9,dataCrop);

% reservoir outlet temperature [oC]
ti101 = I_vector(10,dataCrop);
ti102 = I_vector(11,dataCrop);
ti103 = I_vector(12,dataCrop);

% DP @ erosion boxes [mbar]
dp101 = I_vector(13,dataCrop);
dp102 = I_vector(14,dataCrop);
dp103 = I_vector(15,dataCrop);

% top pressure [mbar g]
% for conversion [bar a]-->[mbar g]
% ptop_n = ptop*10^-3 + 1.01325;
pi101 = I_vector(16,dataCrop);
pi102 = I_vector(17,dataCrop);
pi103 = I_vector(18,dataCrop);

% reservoir pressure [bar g]
% for conversion [bar g]-->[bar a]
% ptop_n = ptop + 1.01325;
pi104 = I_vector(19,dataCrop);

% number of measurements in the data window
dss = size(pi104,2);

%%%%%%%%%%%%%%%%%%
% CODE GOES HERE %
%%%%%%%%%%%%%%%%%%
% check for first iteration
if ~exist('kCheck','var') 
    %initial condition
    [xHat,zHat,~,thetaHat] = InitialConditionHAC(par);

    % Building Dynamic Model
    [diff,alg,x_var,z_var,p_var] = BuildingDynModel(par); 

    % Building NMPC
    solverHAC = BuildingHAC(diff,alg,x_var,z_var,p_var,parPlant,nmpcConfig);

    % first iteration indication    
    kCheck = 1; 
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% diagnostics - estimating the states and the current degradation level %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
yPlant = [fi101;
    fi102;
    fi103;
    1.01325 + 10^-3*pi101; %[mbarg]-->[bar a];
    1.01325 + 10^-3*pi102;
    1.01325 + 10^-3*pi103;
    dp101;
    dp102;
    dp103];

uPlant = [cv101*ones(1,dss); %workaround - i just have the last measurement here. Since it is the disturbance, it doesn't really matter;
    cv102*ones(1,dss);
    cv103*ones(1,dss);
    pi104 + 1.01325];

% since we run the controller with a low frequency, we assume that the last
% 10s are always at steady-state
% uEst = mean(uPlant(:,end - 10:end),2);
% yEst = mean(yPlant(:,end - 10:end),2);
uEst = uPlant;
yEst = yPlant;

[thetaHat,zHat,Psi,flagEst] = HAC_SSEstimation(zHat,thetaHat,uEst,yEst,par);
xHat = DiameterEstimation(xHat,yPlant(1:3,:),yPlant(7:9,:),par);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Solving Health-aware controller %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
[uk,solFlag] = SolvingHAC(solverHAC,xHat,[zHat;yPlant(7:9)],uk(1:3),pi104 + 1.01325,thetak(1:3),thetak(4:6),nmpcConfig);

% compute new values for the valve opening setpoints
% using random values for testing
%o_new = 0.1*ones(3,1) + (0.9*ones(3,1) - 0.1*ones(3,1)).*rand(3,1);
if solFlag
    O_vector = uk;
    Optimization = 1;
else % controller failed
    O_vector = O_vector'; %dummy - doesn't do anything
    Optimization = 0;
end

SS = 0;
Estimation = 0;
Result = 0;
Parameter_Estimation = [thetaHat(1),thetaHat(2),thetaHat(3),thetaHat(4),thetaHat(5),thetaHat(6)];
State_Variables_Estimation = [xHat(1),xHat(2),xHat(3),0,0,0];
State_Variables_Optimization = [0,0,0,0,0,0];
Optimized_Air_Injection = [0,0,0];

