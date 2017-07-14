function [net, wld, retOut, eyeOut, hedOut] = deneve(nSims,headon,ploton)

%Add another input that is plot or not
%Set constants for functions and loops
nIter = 50;
N = 20;
Kw = 1;
sigmaw = 0.37;
K = 20;
v = 1;
sigma = 0.40;

%Create layers ("population codes"). All layers are instances of the deneveLayer class.
%Network layers
net.hid = deneveLayer('hidden',N,N);    %Hidden layer
net.ret = deneveLayer('retinal',1,N);   %Object location on the retina
net.eye = deneveLayer('eye',1,N);       %Eye position signal
net.hed = deneveLayer('head',1,N);      %Object location relative to the head

%World layers
wld.ret = deneveLayer('retinalWorld',1,N);  %Layer to represent world location in retinal coordinates
wld.eye = deneveLayer('eyeWorld',1,N);      %Layer to represent world location in eye centred coordinates
wld.hed = deneveLayer('headWorld',1,N);     %Layer to represent world location in head centred coordinates

%Set the input weights for each network layer. Weights are symmetric, such that the
%input weight from neuron A to B is the same as the input weight from B to A
%weights are stored in temporary variables to be used in inputs
%Function for setting weights could eventually go in class
%Such that weight function is an argument
wfun = @(ind) Kw.*exp((cos((2*pi/N).*ind)-1)/sigmaw^2); %Anonymous function for the bell-shaped input weights
%Preallocate matrices with dimensions [N,N]
tempretw = zeros(N,N,N);
tempeyew = zeros(N,N,N);
temphedw = zeros(N,N,N);
for j=1:N
    for l=1:N
        for m=1:N
            %Pooling weights for each unit in the input/output layers (i.e. an N x N x N matrix)
            tempretw(l,m,j) = wfun(j-l);
            tempeyew(l,m,j) = wfun(j-m);
            temphedw(l,m,j) = wfun(j-l-m);
            
            
            %Pooling weights for each hidden unit  (i.e. an N x N x N matrix for each input layer)
            temphidw{1}(j,l,m) = tempretw(l,m,j);
            temphidw{2}(j,l,m) = tempeyew(l,m,j);
            temphidw{3}(j,l,m) = temphedw(l,m,j);
        end
    end
end

%To do the above as a meshgrid:
% [a,b,c] = meshgrid(1:N,1:N,1:N,);
% tempretw = Kw.*exp((cos((2*pi/N).*(c-b)-1)/sigmaw^2)
% tempeyew = Kw.*exp((cos((2*pi/N).*(c-a)-1)/sigmaw^2)
% temphedw = Kw.*exp((cos((2*pi/N).*(c-a-b)-1)/sigmaw^2)

% temphidw{1} = Kw.*exp((cos((2*pi/N).*(b-a)-1)/sigmaw^2)
% temphidw{2} = Kw.*exp((cos((2*pi/N).*(b-c)-1)/sigmaw^2)
% temphidw{3} = Kw.*exp((cos((2*pi/N).*(b-a-c)-1)/sigmaw^2)

%Calculate input weights for world.  Communication between the eye and ret
%layers with the world are feedforward from the world to the network
%Weights are based on the circular Von Mises function
%Using class weight function
tempWldRet = vmwfun(wld.ret,K,sigma,v);
tempWldEye = vmwfun(wld.eye,K,sigma,v);
tempWldHed = vmwfun(wld.hed,K,sigma,v);

%Specify the network architecture (who talks to whom?)
%keep order of inputs consistent across network inputs
net.hid.setInput({net.ret,net.eye,net.hed},temphidw);
net.ret.setInput({net.hid,wld.ret},{tempretw,tempWldRet});
net.eye.setInput({net.hid,wld.eye},{tempeyew,tempWldEye});

if headon == 1
    net.hed.setInput({net.hid,wld.hed},{temphedw,tempWldHed});
else
    net.hed.setInput({net.hid},{temphedw});
end
    

%=========== Run the simulation ==============
%nSims = 20;
for s = 1:nSims
    %Initialise world layers with random delta functions
    r = zeros(1,N);
    realRetPos = randi(N);
    r(realRetPos)= 1;
    wld.ret.initialise(r);
    r = zeros(1,N);
    realEyePos = randi(N);
    r(realEyePos)= 1;
    wld.eye.initialise(r);
    
    %Switch between delta function and matrix of zeros for head input
    r = zeros(1,N);
    realHedPos = mod((realRetPos + realEyePos),N);   %Change to bais head
    if realHedPos == 0         %Set 0 to 20
        realHedPos = N;
    end
    
    if headon == 1
        r(realHedPos) = 1;
    else
        r(realHedPos) = 0;
    end
    wld.hed.initialise(r);
    
    
    %Vectors logging real positions
    truRet(s) = realRetPos;
    truEye(s) = realEyePos;
    truHed(s) = realHedPos;
    
    %Reset network layers to zero for each simulation
    net.ret.reset(1,N);
    net.eye.reset(1,N);
    net.hed.reset(1,N);
    net.hid.reset(N,N);
    
    for t=1:nIter
        %Switch between world and hidden layer inputs for ret, eye and hed
        isFirstTime=t==1;
        setEnabled(net.ret,net.hid.name,~isFirstTime);
        setEnabled(net.ret,wld.ret.name,isFirstTime);
        setEnabled(net.eye,net.hid.name,~isFirstTime);
        setEnabled(net.eye,wld.eye.name,isFirstTime);
        
        if headon == 1
        setEnabled(net.hed,net.hid.name,~isFirstTime);
        setEnabled(net.hed,wld.hed.name,isFirstTime);
        end
        
        %Update for each time point to include recurrent inputs
        net.hid.update(~isFirstTime);
        net.ret.update(~isFirstTime);
        net.eye.update(~isFirstTime);
        net.hed.update(~isFirstTime);
        
        %Add noise to the response of ret and eye networks at the first
        %time point, from the world input
         if isFirstTime
             addNoise(net.ret);
             addNoise(net.eye);
             %Only add noise to head input if it is activated
             if headon == 1
                 addNoise(net.hed);
             end
         end
         
         est.Ret = pointEstimate(net.ret);
         est.Eye = pointEstimate(net.eye);
         est.Hed = pointEstimate(net.hed);
        
     %============== Plot the simulation==============%
        %Plot vector responses of ret, eye, and hed
        if ploton == 1
            subplot(2,1,1);
            cla
            plotState(net.ret,'linestyle','r-o','linewidth',4);
            plotState(net.eye,'linestyle','b-o','linewidth',4);
            plotState(net.hed,'linestyle','g-o','linewidth',4);

            %Plot 2D matrix response of hid
            subplot(2,1,2);
            cla
            plotState(net.hid);

            %Pauses for plotting
            if t==1
                pause(2)
            else
                pause(0.15);
            end  %2./t);
        end

    end
    
    %Vectors logging estimate positions
    estRet(s) = pointEstimate(net.ret);
    estEye(s) = pointEstimate(net.eye);
    estHed(s) = pointEstimate(net.hed);
end

%========== Statistical Data ===========%
%Calculate wrapped error
errRet = err(net.ret,estRet,truRet);
errEye = err(net.eye,estEye,truEye);
errHed = err(net.hed,estHed,truHed);

%Outputs
retOut = [estRet;truRet;errRet]';
eyeOut = [estEye;truEye;errEye]';
hedOut = [estHed;truHed;errHed]';


keyboard;
end


%gain function here