!--------------------------------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations                              !
!   Copyright 2000-2025 CP2K developers group <https://cp2k.org>                                   !
!                                                                                                  !
!   SPDX-License-Identifier: GPL-2.0-or-later                                                      !
!--------------------------------------------------------------------------------------------------!

! **************************************************************************************************
!> \brief input section for NEGF based quantum transport calculations
!>        (integration with the quantum transport code OMEN)
!>
!> \par History
!>       07.2013 created [Hossein Bani-Hashemian]
!> \author Hossein Bani-Hashemian
! **************************************************************************************************
MODULE input_cp2k_transport
   USE bibliography,                    ONLY: Bruck2014
   USE cp_output_handling,              ONLY: cp_print_key_section_create,&
                                              high_print_level
   USE cp_units,                        ONLY: cp_unit_to_cp2k
   USE input_constants,                 ONLY: &
        injmethod_beyn, injmethod_evp, injsign_negative, injsign_positive, linsolver_banded, &
        linsolver_full, linsolver_mumps, linsolver_pardiso, linsolver_splitsolve, &
        linsolver_superlu, linsolver_umfpack, matrixinv_full, matrixinv_pardiso, matrixinv_pexsi, &
        matrixinv_rgf, neutlead_bs, neutlead_dos, rho_negf, rho_qtbm, rlaxisint_GaussChebyshev, &
        rlaxisint_readfromfile, rlaxisint_trapezoidal, transport_localscf, transport_negf, &
        transport_transmission
   USE input_keyword_types,             ONLY: keyword_create,&
                                              keyword_release,&
                                              keyword_type
   USE input_section_types,             ONLY: section_add_keyword,&
                                              section_add_subsection,&
                                              section_create,&
                                              section_release,&
                                              section_type
   USE input_val_types,                 ONLY: integer_t
   USE kinds,                           ONLY: dp
   USE string_utilities,                ONLY: s2a
#include "./base/base_uses.f90"

   IMPLICIT NONE
   PRIVATE

   CHARACTER(len=*), PARAMETER, PRIVATE :: moduleN = 'input_cp2k_transport'

   PUBLIC :: create_transport_section

CONTAINS

! **************************************************************************************************
!> \brief creates the TRANSPORT section
!> \param[inout] section the section to be created
! **************************************************************************************************
   SUBROUTINE create_transport_section(section)
      TYPE(section_type), POINTER                        :: section

      TYPE(keyword_type), POINTER                        :: keyword
      TYPE(section_type), POINTER                        :: subsection

      CPASSERT(.NOT. ASSOCIATED(section))
      CALL section_create(section, __LOCATION__, name="TRANSPORT", &
                          description="Specifies the parameters for transport, sets parameters for the OMEN code, "// &
                          "see also <https://nano-tcad.ee.ethz.ch>.", &
                          citations=(/Bruck2014/), &
                          n_keywords=29, n_subsections=4, repeats=.FALSE.)

      NULLIFY (keyword)

      CALL keyword_create( &
         keyword, __LOCATION__, name="TRANSPORT_METHOD", &
         description="Preferred method for transport calculations.", &
         usage="TRANSPORT_METHOD <method>", &
         default_i_val=transport_negf, &
         enum_c_vals=s2a("TRANSPORT", "LOCAL_SCF", "TRANSMISSION"), &
         enum_desc=s2a("self-consistent CP2K and OMEN transport calculations", &
                       "CP2K valence Hamiltonian + OMEN self-consistent calculations on conduction electrons", &
                       "self-consistent transmission calculations without applied bias voltage"), &
         enum_i_vals=(/transport_negf, transport_localscf, transport_transmission/))
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create( &
         keyword, __LOCATION__, name="QT_FORMALISM", &
         description="Preferred quantum transport formalism to compute the current and density.", &
         usage="QT_FORMALISM <method>", &
         default_i_val=rho_qtbm, &
         enum_c_vals=s2a("NEGF", "QTBM"), &
         enum_desc=s2a("The non-equilibrium Green's function formalism.", &
                       "The quantum transmitting boundary method / wave-function formalism."), &
         enum_i_vals=(/rho_negf, rho_qtbm/))
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="NUM_POLE", &
                          description="The number of terms in the PEXSI's pole expansion method.", &
                          usage="NUM_POLE <integer>", default_i_val=64)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="N_KPOINTS", &
                          description="The number of k points for determination of the singularities.", &
                          usage="N_KPOINTS <integer>", default_i_val=64)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="NUM_INTERVAL", &
                          description="Max number of energy points per small interval.", &
                          usage="NUM_INTERVAL <integer>", default_i_val=10)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="TASKS_PER_ENERGY_POINT", &
                          description="Number of tasks per energy point. The value should be a divisor of the total "// &
                          "number of MPI ranks.", &
                          usage="TASKS_PER_ENERGY_POINT <integer>", default_i_val=1)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="TASKS_PER_POLE", &
                          description="Number of tasks per pole in the pole expansion method. The value should be a "// &
                          "divisor of the total number of MPI ranks.", &
                          usage="TASKS_PER_POLE <integer>", default_i_val=1)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="GPUS_PER_POINT", &
                          description="Number of GPUs per energy point for SplitSolve. Needs to be a power of two", &
                          usage="GPUS_PER_POINT <integer>", default_i_val=2)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="COLZERO_THRESHOLD", &
                          description="The smallest number that is not zero in the full diagonalization part.", &
                          usage="COLZERO_THRESHOLD <real>", default_r_val=1.0E-12_dp)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="EPS_LIMIT", &
                          description="The smallest eigenvalue that is kept.", &
                          usage="EPS_LIMIT <real>", default_r_val=1.0E-4_dp)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="EPS_LIMIT_CC", &
                          description="The smallest eigenvalue that is kept on the complex contour.", &
                          usage="EPS_LIMIT_CC <real>", default_r_val=1.0E-6_dp)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="EPS_DECAY", &
                          description="The smallest imaginary part that a decaying eigenvalue may have not to be "// &
                          "considered as propagating.", &
                          usage="EPS_DECAY <real>", default_r_val=1.0E-4_dp)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="EPS_SINGULARITY_CURVATURES", &
                          description="Filter for degenerate bands in the bandstructure.", &
                          usage="EPS_SINGULARITY_CURVATURES <real>", default_r_val=1.0E-12_dp)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="EPS_MU", &
                          description="Accuracy to which the Fermi level should be determined.", &
                          usage="EPS_MU <real>", default_r_val=1.0E-6_dp)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="EPS_EIGVAL_DEGEN", &
                          description="Filter for degenerate bands in the injection vector.", &
                          usage="EPS_EIGVAL_DEGEN <real>", default_r_val=1.0E-6_dp)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="EPS_FERMI", &
                          description="Cutoff for the tail of the Fermi function.", &
                          usage="EPS_FERMI <real>", default_r_val=0.0_dp)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="ENERGY_INTERVAL", &
                          description="Distance between energy points in eV.", &
                          usage="ENERGY_INTERVAL <real>", default_r_val=1.0E-3_dp)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="MIN_INTERVAL", &
                          description="Smallest enery distance in energy vector.", &
                          usage="MIN_INTERVAL <real>", default_r_val=1.0E-4_dp)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="TEMPERATURE", &
                          description="Temperature.", &
                          usage="TEMPERATURE [K] 300.0", &
                          default_r_val=cp_unit_to_cp2k(value=300.0_dp, unit_str="K"), &
                          unit_str="K")
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="CSR_SCREENING", &
                          description="Whether distance screening should be applied to improve sparsity of CSR matrices.", &
                          default_l_val=.TRUE., lone_keyword_l_val=.TRUE.)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create( &
         keyword, __LOCATION__, name="LINEAR_SOLVER", &
         description="Preferred solver for solving the linear system of equations.", &
         usage="LINEAR_SOLVER <solver>", &
         default_i_val=linsolver_full, &
         enum_c_vals=s2a("SplitSolve", "SuperLU", "MUMPS", "Full", "Banded", "PARDISO", "UMFPACK"), &
         enum_i_vals=(/linsolver_splitsolve, linsolver_superlu, linsolver_mumps, linsolver_full, linsolver_banded, &
                       linsolver_pardiso, linsolver_umfpack/))
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create( &
         keyword, __LOCATION__, name="MATRIX_INVERSION_METHOD", &
         description="Preferred matrix inversion method.", &
         usage="MATRIX_INVERSION_METHOD <solver>", &
         default_i_val=matrixinv_full, &
         enum_c_vals=s2a("Full", "PEXSI", "PARDISO", "RGF"), &
         enum_i_vals=(/matrixinv_full, matrixinv_pexsi, matrixinv_pardiso, matrixinv_rgf/))
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="INJECTION_METHOD", &
                          description="Method to solve the eigenvalue problem for the open boundary conditions.", &
                          usage="INJECTION_METHOD <method>", &
                          default_i_val=injmethod_beyn, &
                          enum_c_vals=s2a("EVP", "BEYN"), &
                          enum_desc=s2a("Full eigenvalue solver.", &
                                        "Beyn eigenvalue solver."), &
                          enum_i_vals=(/injmethod_evp, injmethod_beyn/))
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create( &
         keyword, __LOCATION__, name="CUTOUT", &
         description="The number of atoms at the beginning and the end of the structure where the density should "// &
         "not be changed.", &
         usage="CUTOUT <integer> <integer>", &
         n_var=2, default_i_vals=(/0, 0/))
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="REAL_AXIS_INTEGRATION_METHOD", &
                          description="Integration method for the real axis.", &
                          usage="REAL_AXIS_INTEGRATION_METHOD <method>", &
                          default_i_val=rlaxisint_GaussChebyshev, &
                          enum_c_vals=s2a("Gauss_Chebyshev", "Trapezoidal_rule", "Read"), &
                          enum_desc=s2a("Gauss-Chebyshev integration between singularity points.", &
                                        "Trapezoidal rule on the total range.", &
                                        "Read integration points from a file (named E.dat)."), &
                          enum_i_vals=(/rlaxisint_GaussChebyshev, rlaxisint_trapezoidal, rlaxisint_readfromfile/))
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="N_POINTS_INV", &
                          description="Number of integration points for the sigma solver on the complex contour.", &
                          usage="N_POINTS_INV <integer>", default_i_val=64)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="OBC_EQUILIBRIUM", &
                          description="Compute the equilibrium density with open boundary conditions.", &
                          default_l_val=.FALSE., lone_keyword_l_val=.TRUE.)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="CONTACT_FILLING", &
                          description="Determination of the contact Fermi levels. Note that this keyword "// &
                          "only works when the TRANSPORT_METHOD is specified as TRANSPORT.", &
                          default_i_val=neutlead_bs, &
                          enum_c_vals=s2a("BAND_STRUCTURE", "DOS"), &
                          enum_desc=s2a("Determine the Fermi levels from the band structure.", &
                                        "Determine the Fermi levels from the density of states."), &
                          enum_i_vals=(/neutlead_bs, neutlead_dos/))
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="DENSITY_MIXING", &
                          description="Mixing parameter for a density mixing in OMEN.", &
                          usage="DENSITY_MIXING <real>", default_r_val=1.0_dp)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      NULLIFY (subsection)

      CALL create_contact_section(subsection)
      CALL section_add_subsection(section, subsection)
      CALL section_release(subsection)

      CALL create_beyn_section(subsection)
      CALL section_add_subsection(section, subsection)
      CALL section_release(subsection)

      CALL create_pexsi_section(subsection)
      CALL section_add_subsection(section, subsection)
      CALL section_release(subsection)

      CALL create_transport_print_section(subsection)
      CALL section_add_subsection(section, subsection)
      CALL section_release(subsection)

   END SUBROUTINE create_transport_section

! **************************************************************************************************
!> \brief Creates the section for creating contacts.
!> \param[inout] section the section to be created
! **************************************************************************************************
   SUBROUTINE create_contact_section(section)
      TYPE(section_type), POINTER                        :: section

      TYPE(keyword_type), POINTER                        :: keyword

      CPASSERT(.NOT. ASSOCIATED(section))
      CALL section_create(section, __LOCATION__, name="CONTACT", &
                          description="Parameters for defining device contacts.", &
                          n_keywords=5, n_subsections=0, repeats=.TRUE.)

      NULLIFY (keyword)

      CALL keyword_create(keyword, __LOCATION__, name="BANDWIDTH", &
                          description="The number of neighboring unit cells that one unit cell interacts with.", &
                          usage="BANDWIDTH <integer>", default_i_val=0)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="START", &
                          description="Index of the first atom in the contact unit cell. Set to 0 to define the contact "// &
                          "unit cell as the first/last N_ATOMS of the structure (after cutout)", &
                          usage="START <integer>", default_i_val=0)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="N_ATOMS", &
                          description="Number of atoms in the contact unit cell.", &
                          usage="N_ATOMS <integer>", default_i_val=0)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="INJECTION_SIGN", &
                          description="Contact unit cell interacts with unit cells to the right (positive) or "// &
                          "to the left (negative).", &
                          usage="INJECTION_SIGN <integer>", &
                          default_i_val=injsign_positive, &
                          enum_c_vals=s2a("POSITIVE", "NEGATIVE"), &
                          enum_desc=s2a("When the contact unit cell is at the upper left corner of the Hamiltonian.", &
                                        "When the contact unit cell is at the lower right corner of the Hamiltonian."), &
                          enum_i_vals=(/injsign_positive, injsign_negative/))
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="INJECTING_CONTACT", &
                          description="whether or not the contact can inject electrons.", &
                          default_l_val=.TRUE., lone_keyword_l_val=.TRUE.)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

   END SUBROUTINE create_contact_section

! **************************************************************************************************
!> \brief Creates the section for the Beyn eigenvalue solver.
!> \param[inout] section the section to be created
! **************************************************************************************************
   SUBROUTINE create_beyn_section(section)
      TYPE(section_type), POINTER                        :: section

      TYPE(keyword_type), POINTER                        :: keyword

      CPASSERT(.NOT. ASSOCIATED(section))
      CALL section_create(section, __LOCATION__, name="BEYN", &
                          description="Parameters for the Beyn eigenvalue solver.", &
                          n_keywords=6, n_subsections=0, repeats=.FALSE.)

      NULLIFY (keyword)

      CALL keyword_create(keyword, __LOCATION__, name="N_RAND", &
                          description="Number of random vectors as a fraction of the size of the unit cell.", &
                          usage="N_RAND <real>", default_r_val=1.0_dp)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="N_RAND_CC", &
                          description="Number of random vectors as a fraction of the size of the unit cell "// &
                          "for the complex contour.", &
                          usage="N_RAND_CC <real>", default_r_val=1.0_dp)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="SVD_CUTOFF", &
                          description="Cutoff for the singular values in the Beyn solver.", &
                          usage="SVD_CUTOFF <real>", default_r_val=1.0_dp)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="N_POINTS_BEYN", &
                          description="Number of integration points per circle in the Beyn solver.", &
                          usage="N_POINTS_BEYN <integer>", default_i_val=32)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="ONE_CIRCLE", &
                          description="Set to .TRUE. if only one circle instead of two should be used in the Beyn solver.", &
                          default_l_val=.FALSE., lone_keyword_l_val=.TRUE.)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="TASKS_PER_INTEGRATION_POINT", &
                          description="Number of tasks per integration point.", &
                          usage="TASKS_PER_INTEGRATION_POINT <integer>", default_i_val=0)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

   END SUBROUTINE create_beyn_section

! **************************************************************************************************
!> \brief Creates the section for the PEXSI solver.
!> \param[inout] section the section to be created
! **************************************************************************************************
   SUBROUTINE create_pexsi_section(section)
      TYPE(section_type), POINTER                        :: section

      TYPE(keyword_type), POINTER                        :: keyword

      CPASSERT(.NOT. ASSOCIATED(section))
      CALL section_create(section, __LOCATION__, name="PEXSI", &
                          description="Parameters for the PEXSI solver to be used within OMEN.", &
                          n_keywords=4, n_subsections=0, repeats=.FALSE., &
                          deprecation_notice="Support for the PEXSI library is slated for removal.")

      NULLIFY (keyword)

      CALL keyword_create(keyword, __LOCATION__, name="ORDERING", &
                          description="Ordering strategy for factorization and selected inversion.", &
                          enum_c_vals=s2a("PARALLEL", "SEQUENTIAL", "MULTIPLE_MINIMUM_DEGREE"), &
                          enum_desc=s2a("Parallel ordering using ParMETIS/PT-SCOTCH (PARMETIS option in SuperLU_DIST)", &
                                        "Sequential ordering using METIS (METIS_AT_PLUS_A option in SuperLU_DIST)", &
                                        "Multiple minimum degree ordering (MMD_AT_PLUS_A option in SuperLU_DIST)"), &
                          enum_i_vals=(/0, 1, 2/), &
                          usage="ORDERING <integer>", default_i_val=1)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="ROW_ORDERING", &
                          description="row permutation strategy for factorization and selected inversion.", &
                          enum_c_vals=s2a("NOROWPERM", "LARGEDIAG"), &
                          enum_desc=s2a("No row permutation (NOROWPERM option in SuperLU_DIST)", &
                                        "Make diagonal entry larger than off diagonal (LargeDiag option in SuperLU_DIST)"), &
                          enum_i_vals=(/0, 1/), &
                          usage="ROW_ORDERING <integer>", default_i_val=0)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="VERBOSITY", &
                          description="The level of output information.", &
                          enum_c_vals=s2a("SILENT", "BASIC", "DETAILED"), &
                          enum_i_vals=(/0, 1, 2/), &
                          usage="VERBOSITY <integer>", default_i_val=0)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="NP_SYMB_FACT", &
                          description="Number of processors for PARMETIS/PT-SCOTCH. Only used if ORDERING is set to PARALLEL. "// &
                          "If 0, the number of processors for PARMETIS/PT-SCOTCH will be set equal to the number of "// &
                          "MPI ranks per pole. Note: if more than one processor is used, a segmentation fault may occur in the "// &
                          "symbolic factorization phase.", &
                          usage="NP_SYMB_FACT <integer>", default_i_val=1)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

   END SUBROUTINE create_pexsi_section

!**************************************************************************************************
!> \brief Creates print section for transport calculations.
!> \param[inout] section the section to be created
! **************************************************************************************************
   SUBROUTINE create_transport_print_section(section)
      TYPE(section_type), POINTER                        :: section

      TYPE(keyword_type), POINTER                        :: keyword
      TYPE(section_type), POINTER                        :: print_key

      CPASSERT(.NOT. ASSOCIATED(section))
      CALL section_create(section, __LOCATION__, name="PRINT", &
                          description="Section of possible print options for transport calculations.", &
                          repeats=.FALSE.)

      NULLIFY (keyword, print_key)
      CALL cp_print_key_section_create(print_key, __LOCATION__, "CURRENT", &
                                       description="Controls the printing of current into cube files.", &
                                       print_level=high_print_level, filename="current")

      CALL keyword_create(keyword, __LOCATION__, name="stride", &
                          description="The stride (X,Y,Z) used to write the cube file "// &
                          "(larger values result in smaller cube files). You can provide 3 numbers (for X,Y,Z) or"// &
                          " 1 number valid for all components.", &
                          usage="STRIDE 2 2 2", n_var=-1, default_i_vals=(/2, 2, 2/), type_of_var=integer_t)
      CALL section_add_keyword(print_key, keyword)
      CALL keyword_release(keyword)
      CALL keyword_create(keyword, __LOCATION__, name="APPEND", &
                          description="append the cube files when they already exist", &
                          default_l_val=.FALSE., lone_keyword_l_val=.TRUE.)
      CALL section_add_keyword(print_key, keyword)
      CALL keyword_release(keyword)

      CALL section_add_subsection(section, print_key)
      CALL section_release(print_key)

   END SUBROUTINE create_transport_print_section

END MODULE input_cp2k_transport
