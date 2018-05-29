 !*****************************************************************************************************!
 !                            Copyright 2008-2018  The ALaDyn Collaboration                            !
 !*****************************************************************************************************!

 !*****************************************************************************************************!
 !  This file is part of ALaDyn.                                                                       !
 !                                                                                                     !
 !  ALaDyn is free software: you can redistribute it and/or modify                                     !
 !  it under the terms of the GNU General Public License as published by                               !
 !  the Free Software Foundation, either version 3 of the License, or                                  !
 !  (at your option) any later version.                                                                !
 !                                                                                                     !
 !  ALaDyn is distributed in the hope that it will be useful,                                          !
 !  but WITHOUT ANY WARRANTY; without even the implied warranty of                                     !
 !  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the                                      !
 !  GNU General Public License for more details.                                                       !
 !                                                                                                     !
 !  You should have received a copy of the GNU General Public License                                  !
 !  along with ALaDyn.  If not, see <http://www.gnu.org/licenses/>.                                    !
 !*****************************************************************************************************!

 module pdf_moments
 use precision_def
 use pic_rutil
 use grid_fields
 use fstruct_data
 use pstruct_data
 use fstruct_data
 use all_param
 contains

 !CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC
 !C
 !C calculates moments for a given pdf-distribution
 !C plus redefining bunch diagnostics
 !C
 !CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC


 SUBROUTINE bunch_diagnostics(bunch_number)
 integer, intent(in) :: bunch_number
 integer :: i
 real(dp) :: moments(2,6)

 !--- general diagnostic function

 CALL bunch_moments_diagnostic(bunch_number)
 CALL bunch_integrated_diagnostics(bunch_number,moments)
 CALL bunch_truncated_diagnostics(bunch_number,moments)
 DO i=1,4
  if(number_of_slices(i)>0) CALL bunch_sliced_diagnostics(bunch_number,moments,number_of_slices(i))
 ENDDO

 if(bunch_number.eq.1) call lineout_Ex(0.0,0.0) !lineout E-field total

 END SUBROUTINE bunch_diagnostics



 !--- --- ---!
 SUBROUTINE bunch_moments_diagnostic(bunch_number)
 integer, intent(in) :: bunch_number
 integer :: n_moment
 real(dp) :: moment(6,8) !firsts 8th moments for: 3-spatial 3-velocity
 real(dp) :: JB(6),JB_S(6),JB_K(6),vs,ek,vk,n_samples !jarque-brera normal-tests variables
 character(1) :: b2str

 !--- 1-8th moments for -x- and -p-
 do n_moment=1,8
  moment(1,n_moment)=calculate_nth_central_moment_bunchMPI(bunch_number,n_moment,1)
  moment(2,n_moment)=calculate_nth_central_moment_bunchMPI(bunch_number,n_moment,2)
  moment(3,n_moment)=calculate_nth_central_moment_bunchMPI(bunch_number,n_moment,3)
  moment(4,n_moment)=calculate_nth_central_moment_bunchMPI(bunch_number,n_moment,4)
  moment(5,n_moment)=calculate_nth_central_moment_bunchMPI(bunch_number,n_moment,5)
  moment(6,n_moment)=calculate_nth_central_moment_bunchMPI(bunch_number,n_moment,6)
 enddo

 !--- Jarque-Brera (Urzula) test
 JB_S  = moment(:,3)/moment(:,2)**(3./2.)
 JB_K  = moment(:,4)/moment(:,2)**2
 n_samples = real(nb_tot(bunch_number),dp)
 vs    = 6. * (n_samples-2.) / (n_samples+1.) / (n_samples+3.)
 ek    = 3. * (n_samples-1.) / (n_samples+1.)
 vk    = 24.* n_samples * (n_samples-2.) * (n_samples-3.) / (n_samples+1.)**2 / (n_samples+3.) / (n_samples+5.)
 JB    = JB_S**2/vs + (JB_K-ek)**2/vk

 !---
 if(pe0) then
  !--- moments output
  write(b2str,'(I1.1)') bunch_number
  open(11,file='diagnostics/bunch_moments_'//b2str//'.dat',form='formatted', position='append')
  write(11,'(100e14.5)') tnow,moment(1,:),moment(2,:),moment(3,:),moment(4,:),moment(5,:),moment(6,:)
  close(11)
  !--- JB-U test output
  open(11,file='diagnostics/JB-U_test_'//b2str//'.dat',form='formatted', position='append')
  write(11,'(100e14.5)') tnow,JB(:)
  close(11)
 endif


 END SUBROUTINE

 !--- --- ---!
 FUNCTION calculate_nth_central_moment_bunchMPI(number_bunch,nth,component)
 integer, intent(in) :: nth, component, number_bunch
 integer :: np
 real(dp) :: mu_mean_local(1),mu_mean(1),moment_local(1),moment(1),nb_tot_inv
 real(dp) :: calculate_nth_central_moment_bunchMPI

 !---
 np=loc_nbpart(imody,imodz,imodx,number_bunch)
 nb_tot_inv = 1.
 if (nb_tot(number_bunch)>0) nb_tot_inv = 1./real(nb_tot(number_bunch),dp)

 !--- mean calculation
 mu_mean_local  = sum( bunch(number_bunch)%part(1:np,component) )
 call allreduce_dpreal(0,mu_mean_local,mu_mean,1)
 mu_mean        = mu_mean * nb_tot_inv

 !--- moment calculation
 moment_local   = sum( ( bunch(number_bunch)%part(1:np,component) - mu_mean(1) )**nth )
 call allreduce_dpreal(0,moment_local,moment,1)
 moment         = moment * nb_tot_inv

 !---
 calculate_nth_central_moment_bunchMPI = moment(1)
 END FUNCTION calculate_nth_central_moment_bunchMPI


 !--- --- ---!
 !-substituting the old function to calculate the integrated diagnostics
 SUBROUTINE bunch_integrated_diagnostics(bunch_number,moments)
 integer, intent(in) :: bunch_number
 integer :: np_local,np
 real(dp),intent(inout) :: moments(2,6)
 real(dp) :: mu_x_local(1), mu_y_local(1), mu_z_local(1) !spatial meam
 real(dp) :: mu_x(1), mu_y(1), mu_z(1) !spatial meam
 real(dp) :: mu_px_local(1), mu_py_local(1), mu_pz_local(1) !momenta mean
 real(dp) :: mu_px(1), mu_py(1), mu_pz(1) !momenta mean
 real(dp) :: s_x_local(1), s_y_local(1), s_z_local(1) !spatial variance
 real(dp) :: s_x(1), s_y(1), s_z(1) !spatial variance
 real(dp) :: s_px_local(1), s_py_local(1), s_pz_local(1) !momenta variance
 real(dp) :: s_px(1), s_py(1), s_pz(1) !momenta variance
 real(dp) :: mu_gamma_local(1), mu_gamma(1) !gamma mean
 real(dp) :: s_gamma_local(1), s_gamma(1) !gamma variance
 real(dp) :: corr_y_py_local(1), corr_z_pz_local(1), corr_x_px_local(1) !correlation transverse plane
 real(dp) :: corr_y_py(1), corr_z_pz(1), corr_x_px(1) !correlation transverse plane
 real(dp) :: emittance_y(1), emittance_z(1) !emittance variables
 real(dp) :: np_inv
 character(1) :: b2str

 !---!
 np_local=loc_nbpart(imody,imodz,imodx,bunch_number)

 !--- mean calculation ---!
 mu_x_local   = sum( bunch(bunch_number)%part(1:np_local,1) )
 mu_y_local   = sum( bunch(bunch_number)%part(1:np_local,2) )
 mu_z_local   = sum( bunch(bunch_number)%part(1:np_local,3) )
 mu_px_local  = sum( bunch(bunch_number)%part(1:np_local,4) )
 mu_py_local  = sum( bunch(bunch_number)%part(1:np_local,5) )
 mu_pz_local  = sum( bunch(bunch_number)%part(1:np_local,6) )
 !---
 call allreduce_dpreal(0,mu_x_local,mu_x,1)
 call allreduce_dpreal(0,mu_y_local,mu_y,1)
 call allreduce_dpreal(0,mu_z_local,mu_z,1)
 call allreduce_dpreal(0,mu_px_local,mu_px,1)
 call allreduce_dpreal(0,mu_py_local,mu_py,1)
 call allreduce_dpreal(0,mu_pz_local,mu_pz,1)
 call allreduce_sint(0,np_local,np)
 !---
 np_inv=1.
 if (np>0) np_inv=1./real(np,dp)

 mu_x  = mu_x * np_inv
 mu_y  = mu_y * np_inv
 mu_z  = mu_z * np_inv
 mu_px = mu_px * np_inv
 mu_py = mu_py * np_inv
 mu_pz = mu_pz * np_inv


 !--- variance calculation ---!
 s_x_local   = sum( ( bunch(bunch_number)%part(1:np_local,1)-mu_x(1)  )**2 )
 s_y_local   = sum( ( bunch(bunch_number)%part(1:np_local,2)-mu_y(1)  )**2 )
 s_z_local   = sum( ( bunch(bunch_number)%part(1:np_local,3)-mu_z(1)  )**2 )
 s_px_local  = sum( ( bunch(bunch_number)%part(1:np_local,4)-mu_px(1) )**2 )
 s_py_local  = sum( ( bunch(bunch_number)%part(1:np_local,5)-mu_py(1) )**2 )
 s_pz_local  = sum( ( bunch(bunch_number)%part(1:np_local,6)-mu_pz(1) )**2 )
 !---
 call allreduce_dpreal(0,s_x_local,s_x,1)
 call allreduce_dpreal(0,s_y_local,s_y,1)
 call allreduce_dpreal(0,s_z_local,s_z,1)
 call allreduce_dpreal(0,s_px_local,s_px,1)
 call allreduce_dpreal(0,s_py_local,s_py,1)
 call allreduce_dpreal(0,s_pz_local,s_pz,1)
 !---
 s_x  = sqrt( s_x  * np_inv )
 s_y  = sqrt( s_y  * np_inv )
 s_z  = sqrt( s_z  * np_inv )
 s_px = sqrt( s_px * np_inv )
 s_py = sqrt( s_py * np_inv )
 s_pz = sqrt( s_pz * np_inv )


 moments(1,1)=mu_x(1)
 moments(1,2)=mu_y(1)
 moments(1,3)=mu_z(1)
 moments(1,4)=mu_px(1)
 moments(1,5)=mu_py(1)
 moments(1,6)=mu_pz(1)
 moments(2,1)=s_x(1)
 moments(2,2)=s_y(1)
 moments(2,3)=s_z(1)
 moments(2,4)=s_px(1)
 moments(2,5)=s_py(1)
 moments(2,6)=s_pz(1)



 !--- gamma diagnostic calculation ---!
 mu_gamma_local  = sum(  sqrt(   1.0 + bunch(bunch_number)%part(1:np_local,4)**2 + &
  bunch(bunch_number)%part(1:np_local,5)**2 + &
  bunch(bunch_number)%part(1:np_local,6)**2 ) )
 !---
 call allreduce_dpreal(0,mu_gamma_local,mu_gamma,1)
 !---
 mu_gamma  = mu_gamma * np_inv
 !--- --- ---!
 s_gamma_local  = sum(  (1.0 + bunch(bunch_number)%part(1:np_local,4)**2 + &
  bunch(bunch_number)%part(1:np_local,5)**2 + &
  bunch(bunch_number)%part(1:np_local,6)**2 ) )
 !---
 call allreduce_dpreal(0,s_gamma_local,s_gamma,1)
 !---
 s_gamma  = s_gamma * np_inv
 if (mu_gamma(1) > 0. .or. mu_gamma(1) < 0.) s_gamma  = s_gamma / mu_gamma(1)**2
 if (s_gamma(1) > 1.) s_gamma  = sqrt(s_gamma-1.)



 !--- emittance calculation ---!
 corr_x_px_local = sum(  (bunch(bunch_number)%part(1:np_local,1)-mu_x(1)) &
  * (bunch(bunch_number)%part(1:np_local,4)-mu_px(1)) )
 corr_y_py_local = sum(  (bunch(bunch_number)%part(1:np_local,2)-mu_y(1)) &
  * (bunch(bunch_number)%part(1:np_local,5)-mu_py(1)) )
 corr_z_pz_local = sum(  (bunch(bunch_number)%part(1:np_local,3)-mu_z(1)) &
  * (bunch(bunch_number)%part(1:np_local,6)-mu_pz(1)) )
 !---
 call allreduce_dpreal(0,corr_x_px_local,corr_x_px,1)
 call allreduce_dpreal(0,corr_y_py_local,corr_y_py,1)
 call allreduce_dpreal(0,corr_z_pz_local,corr_z_pz,1)
 !---
 corr_x_px  = corr_x_px * np_inv
 corr_y_py  = corr_y_py * np_inv
 corr_z_pz  = corr_z_pz * np_inv
 !---
 emittance_y = sqrt( s_y(1)**2 *s_py(1)**2 - corr_y_py(1)**2 )
 emittance_z = sqrt( s_z(1)**2 *s_pz(1)**2 - corr_z_pz(1)**2 )


 !--- output ---!
 if(pe0) then
  write(b2str,'(I1.1)') bunch_number
  open(11,file='diagnostics/bunch_integrated_quantity_'//b2str//'.dat',form='formatted', position='append')
  !1  2   3   4   5    6    7     8      9      10     11      12      13     14    15    16     17       18       19       20
  !t,<X>,<Y>,<Z>,<Px>,<Py>,<Pz>,<rmsX>,<rmsY>,<rmsZ>,<rmsPx>,<rmsPy>,<rmsPz>,<Emy>,<Emz>,<Gam>,DGam/Gam,cov<xPx>,cov<yPy>,cov<zPz>
  write(11,'(100e14.5)') tnow,mu_x,mu_y,mu_z,mu_px,mu_py,mu_pz,s_x,s_y,s_z,s_px,s_py, &
   s_pz,emittance_y,emittance_z,mu_gamma,s_gamma,corr_x_px,corr_y_py,corr_z_pz
  close(11)
 endif



 !---lineout has been placed here---!
 !---only background
 call lineout_background_plasma(100*bunch_number+0, mu_x(1)-4.5*s_x(1), mu_z(1))
 call lineout_background_plasma(100*bunch_number+1, mu_x(1)-3.5*s_x(1), mu_z(1))
 call lineout_background_plasma(100*bunch_number+2, mu_x(1)-2.5*s_x(1), mu_z(1))
 call lineout_background_plasma(100*bunch_number+3, mu_x(1)-1.5*s_x(1), mu_z(1))
 call lineout_background_plasma(100*bunch_number+4, mu_x(1)-0.5*s_x(1), mu_z(1))
 call lineout_background_plasma(100*bunch_number+5, mu_x(1)+0.5*s_x(1), mu_z(1))
 call lineout_background_plasma(100*bunch_number+6, mu_x(1)+1.5*s_x(1), mu_z(1))
 call lineout_background_plasma(100*bunch_number+7, mu_x(1)+2.5*s_x(1), mu_z(1))
 call lineout_background_plasma(100*bunch_number+8, mu_x(1)+3.5*s_x(1), mu_z(1))
 call lineout_background_plasma(100*bunch_number+9, mu_x(1)+4.5*s_x(1), mu_z(1))
 !---background plus bunch density
 call lineout_bunch_and_background_plasma(100*bunch_number+0, mu_x(1)-4.5*s_x(1), mu_z(1))
 call lineout_bunch_and_background_plasma(100*bunch_number+1, mu_x(1)-3.5*s_x(1), mu_z(1))
 call lineout_bunch_and_background_plasma(100*bunch_number+2, mu_x(1)-2.5*s_x(1), mu_z(1))
 call lineout_bunch_and_background_plasma(100*bunch_number+3, mu_x(1)-1.5*s_x(1), mu_z(1))
 call lineout_bunch_and_background_plasma(100*bunch_number+4, mu_x(1)-0.5*s_x(1), mu_z(1))
 call lineout_bunch_and_background_plasma(100*bunch_number+5, mu_x(1)+0.5*s_x(1), mu_z(1))
 call lineout_bunch_and_background_plasma(100*bunch_number+6, mu_x(1)+1.5*s_x(1), mu_z(1))
 call lineout_bunch_and_background_plasma(100*bunch_number+7, mu_x(1)+2.5*s_x(1), mu_z(1))
 call lineout_bunch_and_background_plasma(100*bunch_number+8, mu_x(1)+3.5*s_x(1), mu_z(1))
 call lineout_bunch_and_background_plasma(100*bunch_number+9, mu_x(1)+4.5*s_x(1), mu_z(1))
 !---Ex-field on axis
 !call lineout_Ex(0.,0.)


 END SUBROUTINE bunch_integrated_diagnostics

 !--- --- ---!

 SUBROUTINE bunch_truncated_diagnostics(bunch_number,moments)
 integer, intent(in) :: bunch_number
 integer :: np_local,np
 real(dp),intent(inout) :: moments(2,6)
 real(dp) :: mu_x_local(1), mu_y_local(1), mu_z_local(1) !spatial meam
 real(dp) :: mu_x(1), mu_y(1), mu_z(1) !spatial meam
 real(dp) :: mu_px_local(1), mu_py_local(1), mu_pz_local(1) !momenta mean
 real(dp) :: mu_px(1), mu_py(1), mu_pz(1) !momenta mean
 real(dp) :: s_x_local(1), s_y_local(1), s_z_local(1) !spatial variance
 real(dp) :: s_x(1), s_y(1), s_z(1) !spatial variance
 real(dp) :: s_px_local(1), s_py_local(1), s_pz_local(1) !momenta variance
 real(dp) :: s_px(1), s_py(1), s_pz(1) !momenta variance
 real(dp) :: mu_gamma_local(1), mu_gamma(1) !gamma mean
 real(dp) :: s_gamma_local(1), s_gamma(1) !gamma variance
 real(dp) :: corr_y_py_local(1), corr_z_pz_local(1), corr_x_px_local(1) !correlation transverse plane
 real(dp) :: corr_y_py(1), corr_z_pz(1), corr_x_px(1) !correlation transverse plane
 real(dp) :: emittance_y(1), emittance_z(1) !emittance variables
 real(dp) :: nSigmaCut
 real(dp) :: np_inv
 integer :: ip,nInside_loc
 logical, allocatable :: mask(:)
 character(1) :: b2str

 !---!
 np_local=loc_nbpart(imody,imodz,imodx,bunch_number)


 !---- Mask Calculation ---------!
 allocate (mask(np_local))

 nSigmaCut = 5.0
 nInside_loc=0
 do ip=1,np_local
  mask(ip)=( abs(bunch(bunch_number)%part(ip,1)-moments(1,1))<nSigmaCut*moments(2,1) )&
   .and.(abs(bunch(bunch_number)%part(ip,2)-moments(1,2))<nSigmaCut*moments(2,2) )&
   .and.(abs(bunch(bunch_number)%part(ip,3)-moments(1,3))<nSigmaCut*moments(2,3) )
  if (mask(ip)) nInside_loc=nInside_loc+1
 enddo


 !--- mean calculation ---!
 !--- SUM(x, MASK=MOD(x, 2)==1)   odd elements, sum = 9 ---!

 mu_x_local   = sum( bunch(bunch_number)%part(1:np_local,1), MASK=mask(1:np_local) )
 mu_y_local   = sum( bunch(bunch_number)%part(1:np_local,2), MASK=mask(1:np_local) )
 mu_z_local   = sum( bunch(bunch_number)%part(1:np_local,3), MASK=mask(1:np_local) )
 mu_px_local  = sum( bunch(bunch_number)%part(1:np_local,4), MASK=mask(1:np_local) )
 mu_py_local  = sum( bunch(bunch_number)%part(1:np_local,5), MASK=mask(1:np_local) )
 mu_pz_local  = sum( bunch(bunch_number)%part(1:np_local,6), MASK=mask(1:np_local) )
 !---
 call allreduce_dpreal(0,mu_x_local,mu_x,1)
 call allreduce_dpreal(0,mu_y_local,mu_y,1)
 call allreduce_dpreal(0,mu_z_local,mu_z,1)
 call allreduce_dpreal(0,mu_px_local,mu_px,1)
 call allreduce_dpreal(0,mu_py_local,mu_py,1)
 call allreduce_dpreal(0,mu_pz_local,mu_pz,1)
 call allreduce_sint(0,nInside_loc,np)
 !---
 np_inv=1.
 if (np>0) np_inv=1./real(np,dp)

 mu_x  = mu_x * np_inv
 mu_y  = mu_y * np_inv
 mu_z  = mu_z * np_inv
 mu_px = mu_px * np_inv
 mu_py = mu_py * np_inv
 mu_pz = mu_pz * np_inv


 !--- variance calculation ---!
 s_x_local   = sum( ( bunch(bunch_number)%part(1:np_local,1)-mu_x(1)  )**2, MASK=mask(1:np_local) )
 s_y_local   = sum( ( bunch(bunch_number)%part(1:np_local,2)-mu_y(1)  )**2, MASK=mask(1:np_local) )
 s_z_local   = sum( ( bunch(bunch_number)%part(1:np_local,3)-mu_z(1)  )**2, MASK=mask(1:np_local) )
 s_px_local  = sum( ( bunch(bunch_number)%part(1:np_local,4)-mu_px(1) )**2, MASK=mask(1:np_local) )
 s_py_local  = sum( ( bunch(bunch_number)%part(1:np_local,5)-mu_py(1) )**2, MASK=mask(1:np_local) )
 s_pz_local  = sum( ( bunch(bunch_number)%part(1:np_local,6)-mu_pz(1) )**2, MASK=mask(1:np_local) )
 !---
 call allreduce_dpreal(0,s_x_local,s_x,1)
 call allreduce_dpreal(0,s_y_local,s_y,1)
 call allreduce_dpreal(0,s_z_local,s_z,1)
 call allreduce_dpreal(0,s_px_local,s_px,1)
 call allreduce_dpreal(0,s_py_local,s_py,1)
 call allreduce_dpreal(0,s_pz_local,s_pz,1)
 !---
 s_x  = sqrt( s_x  * np_inv )
 s_y  = sqrt( s_y  * np_inv )
 s_z  = sqrt( s_z  * np_inv )
 s_px = sqrt( s_px * np_inv )
 s_py = sqrt( s_py * np_inv )
 s_pz = sqrt( s_pz * np_inv )


 moments(1,1)=mu_x(1)
 moments(1,2)=mu_y(1)
 moments(1,3)=mu_z(1)
 moments(1,4)=mu_px(1)
 moments(1,5)=mu_py(1)
 moments(1,6)=mu_pz(1)
 moments(2,1)=s_x(1)
 moments(2,2)=s_y(1)
 moments(2,3)=s_z(1)
 moments(2,4)=s_px(1)
 moments(2,5)=s_py(1)
 moments(2,6)=s_pz(1)


 !--- gamma diagnostic calculation ---!
 mu_gamma_local  = sum(  sqrt(   1.0 + bunch(bunch_number)%part(1:np_local,4)**2 + &
  bunch(bunch_number)%part(1:np_local,5)**2 + &
  bunch(bunch_number)%part(1:np_local,6)**2 ), MASK=mask(1:np_local)  )
 !---
 call allreduce_dpreal(0,mu_gamma_local,mu_gamma,1)
 !---
 mu_gamma  = mu_gamma * np_inv
 !--- --- ---!
 s_gamma_local  = sum(  (1.0 + bunch(bunch_number)%part(1:np_local,4)**2 + &
  bunch(bunch_number)%part(1:np_local,5)**2 + &
  bunch(bunch_number)%part(1:np_local,6)**2 ), MASK=mask(1:np_local)  )
 !---
 call allreduce_dpreal(0,s_gamma_local,s_gamma,1)
 !---
 s_gamma  = s_gamma * np_inv
 if (mu_gamma(1) > 0. .or. mu_gamma(1) < 0.) s_gamma  = s_gamma / mu_gamma(1)**2
 if (s_gamma(1) > 1.) s_gamma  = sqrt(s_gamma-1.)



 !--- emittance calculation ---!
 corr_x_px_local = sum(  (bunch(bunch_number)%part(1:np_local,1)-mu_x(1)) &
  * (bunch(bunch_number)%part(1:np_local,4)-mu_px(1)), MASK=mask(1:np_local)  )
 corr_y_py_local = sum(  (bunch(bunch_number)%part(1:np_local,2)-mu_y(1)) &
  * (bunch(bunch_number)%part(1:np_local,5)-mu_py(1)), MASK=mask(1:np_local)  )
 corr_z_pz_local = sum(  (bunch(bunch_number)%part(1:np_local,3)-mu_z(1)) &
  * (bunch(bunch_number)%part(1:np_local,6)-mu_pz(1)), MASK=mask(1:np_local)  )
 !---
 call allreduce_dpreal(0,corr_x_px_local,corr_x_px,1)
 call allreduce_dpreal(0,corr_y_py_local,corr_y_py,1)
 call allreduce_dpreal(0,corr_z_pz_local,corr_z_pz,1)
 !---
 corr_x_px  = corr_x_px * np_inv
 corr_y_py  = corr_y_py * np_inv
 corr_z_pz  = corr_z_pz * np_inv
 !---
 emittance_y = sqrt( s_y(1)**2 *s_py(1)**2 - corr_y_py(1)**2 )
 emittance_z = sqrt( s_z(1)**2 *s_pz(1)**2 - corr_z_pz(1)**2 )


 !--- output ---!
 if(pe0) then
  write(b2str,'(I1.1)') bunch_number
  open(11,file='diagnostics/bunch_truncated_quantity_'//b2str//'.dat',form='formatted', position='append')
  !1  2   3   4   5    6    7     8      9      10     11      12      13     14    15    16     17       18       19       20
  !t,<X>,<Y>,<Z>,<Px>,<Py>,<Pz>,<rmsX>,<rmsY>,<rmsZ>,<rmsPx>,<rmsPy>,<rmsPz>,<Emy>,<Emz>,<Gam>,DGam/Gam,cov<xPx>,cov<yPy>,cov<zPz>
  write(11,'(100e14.5)') tnow,mu_x,mu_y,mu_z,mu_px,mu_py,mu_pz,s_x,s_y,s_z,s_px,s_py, &
   s_pz,emittance_y,emittance_z,mu_gamma,s_gamma,corr_x_px,corr_y_py,corr_z_pz
  close(11)
 endif


 !--- deallocate memory ----!

 deallocate (mask)

 END SUBROUTINE bunch_truncated_diagnostics

 !--- --- ---!

 SUBROUTINE bunch_sliced_diagnostics(bunch_number,moments,number_slices)
 integer, intent(in) :: bunch_number,number_slices
 integer :: np_local,np
 real(dp),intent(in) :: moments(2,6)
 real(dp) :: mu_x_local(1), mu_y_local(1), mu_z_local(1) !spatial meam
 real(dp) :: mu_x(1), mu_y(1), mu_z(1) !spatial meam
 real(dp) :: mu_px_local(1), mu_py_local(1), mu_pz_local(1) !momenta mean
 real(dp) :: mu_px(1), mu_py(1), mu_pz(1) !momenta mean
 real(dp) :: s_x_local(1), s_y_local(1), s_z_local(1) !spatial variance
 real(dp) :: s_x(1), s_y(1), s_z(1) !spatial variance
 real(dp) :: s_px_local(1), s_py_local(1), s_pz_local(1) !momenta variance
 real(dp) :: s_px(1), s_py(1), s_pz(1) !momenta variance
 real(dp) :: mu_gamma_local(1), mu_gamma(1) !gamma mean
 real(dp) :: s_gamma_local(1), s_gamma(1) !gamma variance
 real(dp) :: corr_y_py_local(1), corr_z_pz_local(1), corr_x_px_local(1) !correlation transverse plane
 real(dp) :: corr_y_py(1), corr_z_pz(1), corr_x_px(1) !correlation transverse plane
 real(dp) :: emittance_y(1), emittance_z(1) !emittance variables
 real(dp) :: nSigmaCut,delta_cut
 real(dp) :: np_inv
 integer :: ip,nInside_loc,islice
 logical, allocatable :: mask(:)
 character(1) :: b2str
 character(3) :: nslices2str,islice2str

 !---!
 np_local=loc_nbpart(imody,imodz,imodx,bunch_number)


 !---- Mask Calculation ---------!
 allocate (mask(np_local))


 !---  -5sigma   -4sigma   -3sigma   -2sigma  -1sigma     0sigma   +1sigma   +2sigma    +3sigma   +4sigma   +5sigma
 !---  | slice 0  |    1     |    2    |     3   |     4    |    5    |     6   |     7    |   8    |     9    |   ----!

 do islice=0,number_slices-1 ! change string format in output file for more than 9 slices

  nSigmaCut = 5.0
  delta_cut=2.0*nSigmaCut/number_slices
  nInside_loc=0
  do ip=1,np_local
   mask(ip)=( (bunch(bunch_number)%part(ip,1)-moments(1,1) )>( real(islice-number_slices/2)*delta_cut )*moments(2,1)  ) &
    .and.( (bunch(bunch_number)%part(ip,1)-moments(1,1) )   <( real(islice-number_slices/2+1)*delta_cut)*moments(2,1) )
   if (mask(ip)) nInside_loc=nInside_loc+1
  enddo


  !--- mean calculation ---!
  !--- SUM(x, MASK=MOD(x, 2)==1)   odd elements, sum = 9 ---!

  mu_x_local   = sum( bunch(bunch_number)%part(1:np_local,1), MASK=mask(1:np_local) )
  mu_y_local   = sum( bunch(bunch_number)%part(1:np_local,2), MASK=mask(1:np_local) )
  mu_z_local   = sum( bunch(bunch_number)%part(1:np_local,3), MASK=mask(1:np_local) )
  mu_px_local  = sum( bunch(bunch_number)%part(1:np_local,4), MASK=mask(1:np_local) )
  mu_py_local  = sum( bunch(bunch_number)%part(1:np_local,5), MASK=mask(1:np_local) )
  mu_pz_local  = sum( bunch(bunch_number)%part(1:np_local,6), MASK=mask(1:np_local) )
  !---
  call allreduce_dpreal(0,mu_x_local,mu_x,1)
  call allreduce_dpreal(0,mu_y_local,mu_y,1)
  call allreduce_dpreal(0,mu_z_local,mu_z,1)
  call allreduce_dpreal(0,mu_px_local,mu_px,1)
  call allreduce_dpreal(0,mu_py_local,mu_py,1)
  call allreduce_dpreal(0,mu_pz_local,mu_pz,1)
  call allreduce_sint(0,nInside_loc,np)
  !---
  np_inv=1.
  if (np>0) np_inv=1./real(np,dp)
  mu_x  = mu_x * np_inv
  mu_y  = mu_y * np_inv
  mu_z  = mu_z * np_inv
  mu_px = mu_px * np_inv
  mu_py = mu_py * np_inv
  mu_pz = mu_pz * np_inv


  !--- variance calculation ---!
  s_x_local   = sum( ( bunch(bunch_number)%part(1:np_local,1)-mu_x(1)  )**2, MASK=mask(1:np_local) )
  s_y_local   = sum( ( bunch(bunch_number)%part(1:np_local,2)-mu_y(1)  )**2, MASK=mask(1:np_local) )
  s_z_local   = sum( ( bunch(bunch_number)%part(1:np_local,3)-mu_z(1)  )**2, MASK=mask(1:np_local) )
  s_px_local  = sum( ( bunch(bunch_number)%part(1:np_local,4)-mu_px(1) )**2, MASK=mask(1:np_local) )
  s_py_local  = sum( ( bunch(bunch_number)%part(1:np_local,5)-mu_py(1) )**2, MASK=mask(1:np_local) )
  s_pz_local  = sum( ( bunch(bunch_number)%part(1:np_local,6)-mu_pz(1) )**2, MASK=mask(1:np_local) )
  !---
  call allreduce_dpreal(0,s_x_local,s_x,1)
  call allreduce_dpreal(0,s_y_local,s_y,1)
  call allreduce_dpreal(0,s_z_local,s_z,1)
  call allreduce_dpreal(0,s_px_local,s_px,1)
  call allreduce_dpreal(0,s_py_local,s_py,1)
  call allreduce_dpreal(0,s_pz_local,s_pz,1)
  !---
  s_x  = sqrt( s_x  * np_inv )
  s_y  = sqrt( s_y  * np_inv )
  s_z  = sqrt( s_z  * np_inv )
  s_px = sqrt( s_px * np_inv )
  s_py = sqrt( s_py * np_inv )
  s_pz = sqrt( s_pz * np_inv )



  !--- gamma diagnostic calculation ---!
  mu_gamma_local  = sum(  sqrt(   1.0 + bunch(bunch_number)%part(1:np_local,4)**2 + &
   bunch(bunch_number)%part(1:np_local,5)**2 + &
   bunch(bunch_number)%part(1:np_local,6)**2 ), MASK=mask(1:np_local)  )
  !---
  call allreduce_dpreal(0,mu_gamma_local,mu_gamma,1)
  !---
  mu_gamma  = mu_gamma * np_inv
  !--- --- ---!
  s_gamma_local  = sum(  (1.0 + bunch(bunch_number)%part(1:np_local,4)**2 + &
   bunch(bunch_number)%part(1:np_local,5)**2 + &
   bunch(bunch_number)%part(1:np_local,6)**2 ), MASK=mask(1:np_local)  )
  !---
  call allreduce_dpreal(0,s_gamma_local,s_gamma,1)
  !---
  s_gamma  = s_gamma * np_inv
  if (mu_gamma(1) > 0. .or. mu_gamma(1) < 0.) s_gamma  = s_gamma / mu_gamma(1)**2
  if (s_gamma(1) > 1.) s_gamma  = sqrt(s_gamma-1.)



  !--- emittance calculation ---!
  corr_x_px_local = sum(  (bunch(bunch_number)%part(1:np_local,1)-mu_x(1)) &
   * (bunch(bunch_number)%part(1:np_local,4)-mu_px(1)), MASK=mask(1:np_local)  )
  corr_y_py_local = sum(  (bunch(bunch_number)%part(1:np_local,2)-mu_y(1)) &
   * (bunch(bunch_number)%part(1:np_local,5)-mu_py(1)), MASK=mask(1:np_local)  )
  corr_z_pz_local = sum(  (bunch(bunch_number)%part(1:np_local,3)-mu_z(1)) &
   * (bunch(bunch_number)%part(1:np_local,6)-mu_pz(1)), MASK=mask(1:np_local)  )

  !---
  call allreduce_dpreal(0,corr_x_px_local,corr_x_px,1)
  call allreduce_dpreal(0,corr_y_py_local,corr_y_py,1)
  call allreduce_dpreal(0,corr_z_pz_local,corr_z_pz,1)
  !---
  corr_x_px  = corr_x_px * np_inv
  corr_y_py  = corr_y_py * np_inv
  corr_z_pz  = corr_z_pz * np_inv
  !---
  emittance_y = sqrt( s_y(1)**2 *s_py(1)**2 - corr_y_py(1)**2 )
  emittance_z = sqrt( s_z(1)**2 *s_pz(1)**2 - corr_z_pz(1)**2 )


  !--- output ---!
  if(pe0) then
   write(b2str,'(I1.1)') bunch_number
   write(nslices2str,'(I3.3)') number_slices
   write(islice2str, '(I3.3)') islice
   open(11,file='diagnostics/bunch_sliced_quantity_'//b2str//'_'//nslices2str//'_'//islice2str//'.dat', &
    form='formatted', position='append')
   !1  2   3   4   5    6    7     8      9      10     11      12      13     14    15    16     17       18       19       20
   !t,<X>,<Y>,<Z>,<Px>,<Py>,<Pz>,<rmsX>,<rmsY>,<rmsZ>,<rmsPx>,<rmsPy>,<rmsPz>,<Emy>,<Emz>,<Gam>,DGam/Gam,cov<xPx>,cov<yPy>,cov<zPz>
   write(11,'(100e14.5)') tnow,mu_x,mu_y,mu_z,mu_px,mu_py,mu_pz,s_x,s_y,s_z,s_px,s_py, &
    s_pz,emittance_y,emittance_z,mu_gamma,s_gamma,corr_x_px,corr_y_py,corr_z_pz
   close(11)
  endif

 enddo ! end loop on slices

 !--- deallocate memory ----!
 deallocate (mask)

 END SUBROUTINE bunch_sliced_diagnostics


 !--- lineout only for the background gas ---!
 SUBROUTINE lineout_background_plasma(bunch_number,cut_x,cut_z)
 integer,intent(in) :: bunch_number
 real(dp),intent(in) :: cut_x, cut_z
 integer :: i,i1,i2,j1,k1,nyp,nzp
 integer :: i_section,k_section,iy1,iy2
 real(dp) :: x1,z1,x2,z2
 real(dp),allocatable :: rho_in(:),rho_out(:)
 character(3) :: b2str

 j1=loc_ygrid(imody)%p_ind(1)
 nyp=loc_ygrid(imody)%p_ind(2)
 k1=loc_zgrid(imodz)%p_ind(1)
 nzp=loc_zgrid(imodz)%p_ind(2)
 i1=loc_xgrid(imodx)%p_ind(1)
 i2=loc_xgrid(imodx)%p_ind(2)
 x1=loc_xgrid(imodx)%gmin
 z1=loc_zgrid(imodz)%gmin
 x2=loc_xgrid(imodx)%gmax
 z2=loc_zgrid(imodz)%gmax

 allocate(rho_in(ny),rho_out(ny))
 rho_in=0.0
 rho_out=0.0

 if(cut_z> z1.and.cut_z<=z2)then
  if(cut_x> x1.and.cut_x<= x2)then
   i_section=i1+int(dx_inv*(cut_x-x1))
   k_section=k1+int(dz_inv*(cut_z-z1))
   iy1=1+imody*ny_loc
   iy2=iy1+ny_loc-1
   rho_in(iy1:iy2)=jc(i_section,j1:nyp,k_section,2)
  endif
 endif
 call allreduce_dpreal(SUMV,rho_in,rho_out,ny)

 !--- output ---!
 if(pe0) then
  write(b2str,'(I3.3)') bunch_number
  open(11,file='diagnostics/lineout_background_'//b2str//'.dat',form='formatted',position='append')
  write(11,'(1000e14.5)') (rho_out(i),i=1,ny)
  close(11)
 endif

 if( allocated(rho_in)  )  deallocate(rho_in)
 if( allocated(rho_out) )  deallocate(rho_out)
 END SUBROUTINE


 !--- lineout for: background density + bunch density ---!
 SUBROUTINE lineout_bunch_and_background_plasma(bunch_number,cut_x,cut_z)
 integer,intent(in) :: bunch_number
 real(dp),intent(in) :: cut_x, cut_z
 integer :: i,i1,i2,j1,k1,nyp,nzp
 integer :: i_section,k_section,iy1,iy2
 real(dp) :: x1,z1,x2,z2
 real(dp),allocatable :: rho_in(:),rho_out(:)
 character(3) :: b2str

 j1=loc_ygrid(imody)%p_ind(1)
 nyp=loc_ygrid(imody)%p_ind(2)
 k1=loc_zgrid(imodz)%p_ind(1)
 nzp=loc_zgrid(imodz)%p_ind(2)
 i1=loc_xgrid(imodx)%p_ind(1)
 i2=loc_xgrid(imodx)%p_ind(2)
 x1=loc_xgrid(imodx)%gmin
 z1=loc_zgrid(imodz)%gmin
 x2=loc_xgrid(imodx)%gmax
 z2=loc_zgrid(imodz)%gmax

 allocate(rho_in(ny),rho_out(ny))
 rho_in=0.0
 rho_out=0.0

 if(cut_z> z1.and.cut_z<=z2)then
  if(cut_x> x1.and.cut_x<= x2)then
   i_section=i1+int(dx_inv*(cut_x-x1))
   k_section=k1+int(dz_inv*(cut_z-z1))
   iy1=1+imody*ny_loc
   iy2=iy1+ny_loc-1
   rho_in(iy1:iy2)=jc(i_section,j1:nyp,k_section,1)
  endif
 endif
 call allreduce_dpreal(SUMV,rho_in,rho_out,ny)

 !--- output ---!
 if(pe0) then
  write(b2str,'(I3.3)') bunch_number
  open(11,file='diagnostics/lineout_bunch_and_background_'//b2str//'.dat',form='formatted',position='append')
  write(11,'(1000e14.5)') (rho_out(i),i=1,ny)
  close(11)
 endif

 if( allocated(rho_in)  )  deallocate(rho_in)
 if( allocated(rho_out) )  deallocate(rho_out)
 END SUBROUTINE


 !--- lineout for: Ex (on axis) ---!
 SUBROUTINE lineout_Ex(cut_y,cut_z)
 real(dp),intent(in) :: cut_y, cut_z
 integer :: i,i1,i2,j1,k1,nyp,nzp
 integer :: j_section,k_section,ix1,iy1,ix2,iy2
 real(dp) :: x1,y1,z1,x2,y2,z2
 real(dp),allocatable :: rho_in(:),rho_out(:)

 j1=loc_ygrid(imody)%p_ind(1)
 k1=loc_zgrid(imodz)%p_ind(1)
 nyp=loc_ygrid(imody)%p_ind(2)
 nzp=loc_zgrid(imodz)%p_ind(2)

 i1=loc_xgrid(imodx)%p_ind(1)
 i2=loc_xgrid(imodx)%p_ind(2)

 x1=loc_xgrid(imodx)%gmin
 y1=loc_ygrid(imody)%gmin
 z1=loc_zgrid(imodz)%gmin
 x2=loc_xgrid(imodx)%gmax
 y2=loc_ygrid(imody)%gmax
 z2=loc_zgrid(imodz)%gmax

 allocate(rho_in(nx),rho_out(nx))
 rho_in=0.0
 rho_out=0.0

 if(cut_z> z1.and.cut_z<=z2)then
  if(cut_y> y1.and.cut_y<= y2)then
   j_section=j1+int(dy_inv*(cut_y-y1))
   k_section=k1+int(dz_inv*(cut_z-z1))
   iy1=1+imody*ny_loc
   iy2=iy1+ny_loc-1
   ix1=1+imodx*nx_loc
   ix2=ix1+nx_loc-1
   rho_in(ix1:ix2)=ebf_bunch(i1:i2,j_section,k_section,1) + &
    ebf(i1:i2,j_section,k_section,1)
  endif
 endif
 call allreduce_dpreal(SUMV,rho_in,rho_out,nx)

 !--- output ---!
 if(pe0) then
  open(11,file='diagnostics/lineout_Ex_onaxis.dat',form='formatted',position='append')
  write(11,'(1000e14.5)') (rho_out(i),i=1,nx)
  close(11)
 endif

 if( allocated(rho_in)  )  deallocate(rho_in)
 if( allocated(rho_out) )  deallocate(rho_out)
 END SUBROUTINE




 end module pdf_moments
