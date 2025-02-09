
close all; clc;clear;
set(0,'DefaultFigureWindowStyle','docked') %'normal' 'docked'
set(0,'defaulttextInterpreter','latex');
set(groot, 'defaultAxesTickLabelInterpreter','latex'); set(groot, 'defaultLegendInterpreter','latex');
%Let us change now the usual grey background of the matlab figures to white
set(0,'defaultfigurecolor',[1 1 1])

import casadi.*
addpath(genpath('./../../submodules/minvo/src/utils'));
addpath(genpath('./../../submodules/minvo/src/solutions'));
addpath(genpath('./more_utils'));

opti = casadi.Opti();
deg_pos_prediction=2;  
dim_pos=3;
num_seg_prediction =2; %number of segments


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%    PREDICTION     %%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
t0=0;
tf=10.5;
all_t=linspace(t0,tf,10);      

all_pos=MX.sym('all_pos',dim_pos,10);

sp_tmp=MyClampedUniformSpline(t0,tf,deg_pos_prediction, dim_pos, num_seg_prediction, opti);  %creating another object to not mess up with sy

% all_yaw=MX.sym('lambda1',1,numel(t_simpson));
cost_function=0;
for i=1:size(all_pos,2)
    dist=sp_tmp.getPosT(all_t(i))-all_pos(:,i);
    cost_function = cost_function + dist'*dist; 
end

% lambda1=MX.sym('lambda1',1,1);
% lambda2=MX.sym('lambda2',1,1);
% lambda3=MX.sym('lambda3',1,1);

% c1= sy_tmp.getPosT(t0) - y0; %==0
% c2= sy_tmp.getVelT(t0) - ydot0; %==0
% c3= sy_tmp.getVelT(tf) - ydotf; %==0

lagrangian = cost_function; %  +  lambda1*c1 + lambda2*c2 + lambda3*c3;

variables=[sp_tmp.getCPsAsMatrix()];% lambda1 lambda2  lambda3];

kkt_eqs=jacobian(lagrangian, variables)'; %I want kkt=[0 0 ... 0]'

%Obtain A and b
b=-casadi.substitute(kkt_eqs, variables, zeros(size(variables))); %Note the - sign
A=jacobian(kkt_eqs, variables);

solution=A\b;  %Solve the system of equations

solution=reshape(solution,dim_pos,numel(solution)/dim_pos);

sp_tmp.updateCPsWithSolution(full(solution));


coeff_predicted=getCoeffPredictedPoly(sp_tmp);


f= Function('f', {all_pos}, [{solution, coeff_predicted}], ...
                 {'all_pos'}, {'solution', 'coeff_predicted'} );
% f=f.expand();

all_pos_value= [linspace(0.0,10,size(all_pos,2));
                linspace(0.0,10,size(all_pos,2));
                linspace(0.0,10,size(all_pos,2))] + 4*rand(dim_pos,size(all_pos,2));

tic
sol=f('all_pos',all_pos_value);
toc
sol.solution
sol.coeff_predicted

sp_tmp.updateCPsWithSolution(full(sol.solution));
sp_tmp.plotPosVelAccelJerk();
subplot(4,1,1); hold on;
plot(all_t, all_pos_value, 'o')
t=sym('t');
Pt=full(sol.coeff_predicted)*[t^2;t;1];
fplot(Pt,[tf,tf+4],'--')
subplot(4,1,2); hold on;
fplot(diff(Pt,t),[tf,tf+4],'--')
subplot(4,1,3); hold on;
fplot(diff(Pt,t,2),[tf,tf+4],'--')


% f.save('predictor.casadi') %The file generated is quite big

%Write param file with the characteristics of the casadi function generated
my_file=fopen('params_casadi_prediction.yaml','w'); %Overwrite content. This will clear its content
fprintf(my_file,'#DO NOT EDIT. Automatically generated by MATLAB\n');
fprintf(my_file,'#If you want to change a parameter, change it in prediction.m and run that file again\n');
fprintf(my_file,'num_seg_prediction: %d\n',num_seg_prediction);
fprintf(my_file,'deg_pos_prediction: %d\n',deg_pos_prediction);
%Note that deg_pos_prediction is not needed in the C++ file


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%    PREDICTION     %%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
sp_tmp=MyClampedUniformSpline(t0,tf,deg_pos_prediction, dim_pos, num_seg_prediction, opti);  %creating another object to not mess up with sy

name='predictor_kkt_Ab_';
delete([name '*.casadi'])
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Note that here the value of t0 and tf won't affect anything
all_f={};
for j=1:num_seg_prediction
    u=MX.sym('u',1,1);
    pos_observed=MX.sym('pos',3,1);
    dist=sp_tmp.getPosU(u,j)-pos_observed; %t0 and tf don't affect getPosU()
    term_cost_function = dist'*dist;
    variables=sp_tmp.getCPsAsMatrix();%[sp_tmp.getCPsofIntervalAsMatrix(j)];% lambda1 lambda2  lambda3];
    kkt_eqs=jacobian(term_cost_function, variables)'; %I want kkt=[0 0 ... 0]'
    b=-casadi.substitute(kkt_eqs, variables, zeros(size(variables))); %Note the - sign
    A=jacobian(kkt_eqs, variables);
    f= Function('f', {pos_observed, u}, [{A, b}], ...
                     {'pos','u'}, {'A', 'b'} );
    f=f.expand();
    f.save([name num2str(j) '.casadi'])
    all_f{j}=f;
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% End of 'note that here...'

A=zeros(size(A)); b=zeros(size(b));
for k=1:size(all_pos,2)
    
    t=all_t(:,k);
    pos=all_pos_value(:,k);
    
    j=sp_tmp.getIndexIntervalforT(t);
    u=sp_tmp.t2u(t);
    result=all_f{j}('pos',pos,'u',u);
    A=A+result.A;
    b=b+result.b;
    
end

A=convertMX2Matlab(A);
b=convertMX2Matlab(b);

invA_b_solved=A\b;
reshape(invA_b_solved,3,[])

%%%%%%%%%%%%%%%%%%%%%%%

t0_var=MX.sym('t0',1,1); 
tf_var=MX.sym('tf',1,1);
sp_tmp=MyClampedUniformSpline(t0_var,tf_var,deg_pos_prediction, dim_pos, num_seg_prediction, opti);
invA_b=MX.sym('invA_b',1,3*sp_tmp.num_cpoints);
solution_reshaped=reshape(invA_b,3,numel(invA_b)/3);
sp_tmp.updateCPsWithSolution(solution_reshaped);
coeff_predicted=getCoeffPredictedPoly(sp_tmp);

name='predictor_coeff_predicted.casadi';
delete(name);
g= Function('g', {t0_var, tf_var, invA_b}, [{coeff_predicted}], ...
                  {'t0','tf','invA_b'}, {'coeff_predicted'} );
g=g.expand();
g.save([name]);
              
tmp=g('t0',t0,'tf',tf,'invA_b',invA_b_solved)             
tmp.coeff_predicted

% convertMX2Matlab(tmp.coeff_predicted*[tf^2, tf, 1]')


function result=getCoeffPredictedPoly(sp_tmp)
    xf=sp_tmp.getPosU(1.0,sp_tmp.num_seg); %I could also use getPosT(tf);
    vf=sp_tmp.getVelU(1.0,sp_tmp.num_seg); 
    af=sp_tmp.getAccelU(1.0,sp_tmp.num_seg);

    %Obtain the coefficients
    % xf+vf*(t-tf) + 0.5*af*(t-tf)^2   \equiv 
    % xf+vf*t - vf*tf + 0.5*af*t^2 -af*tf*t + 0.5*af*tf^2;  \equiv 
    % (0.5*af)*t^2 + (vf - af*tf)*t +  (xf+0.5*af*tf^2 - vf*tf )      

    tf=max(sp_tmp.knots);
    
    a=0.5*af;
    b=vf-af*tf;
    c=xf+0.5*af*tf^2- vf*tf;    
    
    result=[a b c];
    %obtain the coefficients (second way to do it, slower)
    % t=MX.sym('t',1,1);
    % poly_predicted=xf+vf*(t-tf) + 0.5*af*(t-tf)^2;
    % c=substitute(poly_predicted, t, 0.0);
    % b=substitute(jacobian(poly_predicted,t), t, 0.0);
    % a=(1/2)*substitute(jacobian(jacobian(poly_predicted,t),t), t, 0.0);
end